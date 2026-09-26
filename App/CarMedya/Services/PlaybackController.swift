import AVFoundation
import CarMediaCore
import CarMediaKit
import Combine
import os
import UIKit

/// The single player of the app, shared by the phone UI, lock screen and CarPlay.
///
/// - Audio session: `.playback` / `.longFormAudio`, active **only while playing** so the car's own
///   sources are not interrupted when nothing plays (plan §5, App Review 2.5.4).
/// - Errors are classified with ``UserFacingError`` and details redacted with the Xtream password.
/// - Lock screen / CarPlay Now Playing goes through ``NowPlayingInfoPublisher`` (iOS 17–26 APIs).
@MainActor
final class PlaybackController: ObservableObject {
    static let shared = PlaybackController()

    /// Player state for all surfaces.
    @Published private(set) var state = NowPlayingState()
    /// Whether the full-screen phone player is shown.
    @Published var isPlayerPresented = false
    /// When the sleep timer pauses playback, if set.
    @Published private(set) var sleepDeadline: Date?

    /// The one AVPlayer (also used by `VideoPlayerView` and AirPlay).
    let player = AVPlayer()

    private let resolver = PlaybackURLResolver()
    private let nowPlaying = NowPlayingInfoPublisher()
    private var itemObservers = Set<AnyCancellable>()
    private var observers = Set<AnyCancellable>()
    private var timeObserver: Any?
    private var secrets: [String] = []
    private var artwork: UIImage?
    private var isSessionActive = false
    /// Route-sharing policy of the active session: long-form video for movies/TV, long-form audio for radio.
    private var sessionPolicy: AVAudioSession.RouteSharingPolicy = .longFormAudio
    /// Position to seek to once the current item is ready (continue watching).
    private var pendingStart: TimeInterval?
    /// Request of the current item, replayed by automatic reconnection.
    private var currentRequest: PlaybackRequest?
    private var reconnect = ReconnectPolicy()
    private var reconnectTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.bnycftc.carmedya", category: "playback")

    private init() {
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        player.automaticallyWaitsToMinimizeStalling = true
        observePlayer()
        observeAudioSession()
        nowPlaying.configureRemoteCommands()
    }

    // MARK: Commands

    /// Starts `channel`. `queue` is the list it was picked from (next/previous and CarPlay skipping).
    /// `startAt` resumes on-demand content at a saved position.
    func play(_ channel: Channel, queue: [Channel] = [], presentPlayer: Bool = true, startAt: TimeInterval? = nil) {
        saveProgressOfCurrentItem()
        pendingStart = nil
        cancelReconnect()
        reconnect.reset()
        currentRequest = nil
        let model = AppModel.shared
        let record = model.record(forChannelID: channel.id)
        let isXtream = record?.source.isXtream ?? false
        secrets = isXtream ? xtreamSecrets(sourceID: record?.id) : []
        artwork = nil

        switch resolver.resolve(channel, isXtreamSource: isXtream) {
        case .unsupported(let reason):
            tearDownItem()
            state.reject(channel, reason: reason, queue: queue)
            deactivateSession()
        case .playable(let request):
            state.begin(channel, request: request, queue: queue)
            if channel.kind == .live {
                state.programmeTitle = model.epgSummary(for: channel, at: Date())?.now?.title
            }
            pendingStart = request.isLive ? nil : startAt.flatMap { $0 > 0 ? $0 : nil }
            currentRequest = request
            load(request)
        }
        if channel.kind == .live {
            model.recordPlayed(channel.id)
        }
        if presentPlayer {
            isPlayerPresented = true
        }
        publishNowPlaying()
        loadArtwork(for: channel)
    }

    func resume() {
        guard let channel = state.channel else { return }
        if state.isFailed || player.currentItem == nil {
            play(channel, queue: state.queue, presentPlayer: false)
            return
        }
        activateSession()
        if state.isLive {
            // Rejoin the live edge instead of resuming a stale buffer.
            player.currentItem?.seek(to: .positiveInfinity, completionHandler: nil)
        }
        player.play()
    }

    func pause() {
        cancelReconnect()
        saveProgressOfCurrentItem()
        CatalogModel.shared.flush()
        player.pause()
        state.markPaused()
        deactivateSession()
        publishNowPlaying()
    }

    func togglePlayPause() {
        if state.isPlaying || state.phase == .loading { pause() } else { resume() }
    }

    func stop() {
        cancelReconnect()
        setSleepTimer(nil)
        saveProgressOfCurrentItem()
        CatalogModel.shared.flush()
        tearDownItem()
        state.stop()
        isPlayerPresented = false
        deactivateSession()
        nowPlaying.clear()
    }

    func playNext() {
        guard let next = state.nextChannel else { return }
        play(next, queue: state.queue, presentPlayer: false)
    }

    func playPrevious() {
        guard let previous = state.previousChannel else { return }
        play(previous, queue: state.queue, presentPlayer: false)
    }

    /// Seeks on-demand content. Ignored for live streams.
    func seek(to seconds: TimeInterval) {
        guard state.canSeek else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    /// Pauses after `minutes` (or at `date`); `nil` turns the timer off.
    func setSleepTimer(_ minutes: Int?) {
        setSleepTimer(until: minutes.map { Date().addingTimeInterval(TimeInterval($0) * 60) })
    }

    func setSleepTimer(until date: Date?) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepDeadline = date
        guard let date else { return }
        sleepTask = Task { [weak self] in
            let seconds = max(0, date.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.sleepDeadline = nil
            self.sleepTask = nil
            self.pause()
        }
    }

    /// Retries the current channel after a failure.
    func retry() {
        guard let channel = state.channel else { return }
        play(channel, queue: state.queue, presentPlayer: false)
    }

    /// Enables channel skipping on the lock screen and in CarPlay (Settings).
    func setChannelSkipEnabled(_ enabled: Bool) {
        nowPlaying.setSkipEnabled(enabled)
    }

    // MARK: Loading

    private func load(_ request: PlaybackRequest) {
        tearDownItem()
        var options: [String: Any] = [:]
        if let userAgent = request.userAgent {
            // Public since iOS 16. There is no public option for arbitrary headers (e.g. Referer), and
            // private AVURLAsset keys are off-limits (CLAUDE.md), so such streams may be refused by the server.
            options[AVURLAssetHTTPUserAgentKey] = userAgent
        }
        if request.referrer != nil {
            log.info("Stream asks for a Referer header, which AVFoundation cannot send")
        }
        let asset = AVURLAsset(url: request.url, options: options)
        let item = AVPlayerItem(asset: asset)
        observe(item)
        player.replaceCurrentItem(with: item)
        sessionPolicy = request.isAudioOnly ? .longFormAudio : .longFormVideo
        activateSession()
        player.play()
    }

    private func tearDownItem() {
        itemObservers.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func observe(_ item: AVPlayerItem) {
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak item] status in
                guard let item else { return }
                switch status {
                case .failed:
                    PlaybackController.shared.handleFailure(item.error)
                case .readyToPlay:
                    PlaybackController.shared.handleReadyToPlay()
                default:
                    break
                }
            }
            .store(in: &itemObservers)

        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                PlaybackController.shared.handleFailure(error)
            }
            .store(in: &itemObservers)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                PlaybackController.shared.handleDidPlayToEnd()
            }
            .store(in: &itemObservers)
    }

    private func observePlayer() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { status in
                PlaybackController.shared.handleTimeControlStatus(status)
            }
            .store(in: &observers)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 2),
            queue: .main
        ) { time in
            let seconds = time.seconds
            Task { @MainActor in PlaybackController.shared.handleTick(seconds) }
        }
    }

    private func observeAudioSession() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                PlaybackController.shared.handleInterruption(notification)
            }
            .store(in: &observers)

        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                PlaybackController.shared.handleRouteChange(notification)
            }
            .store(in: &observers)
    }

    // MARK: Event handling

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        guard state.isActive, !state.isFailed else { return }
        switch status {
        case .playing:
            state.markPlaying()
            state.reconnectAttempt = nil
            reconnect.markPlaying(at: Date())
            cancelStallTimer()
        case .waitingToPlayAtSpecifiedRate:
            state.markBuffering()
            reconnect.markInterrupted(at: Date())
            startStallTimerIfLive()
        case .paused:
            if state.phase != .loading { state.markPaused() }
        @unknown default:
            break
        }
        publishNowPlaying()
    }

    private func handleTick(_ seconds: Double) {
        guard state.isActive, !state.isLive else { return }
        let duration = player.currentItem?.duration.seconds
        state.updateTime(elapsed: seconds, duration: duration)
        // Until the resume seek has happened the position is 0; recording it would be meaningless.
        guard pendingStart == nil, let channel = state.channel, channel.kind != .live else { return }
        CatalogModel.shared.recordProgress(
            channelID: channel.id, position: seconds, duration: Self.finiteDuration(duration)
        )
    }

    private func handleReadyToPlay() {
        guard let start = pendingStart else { return }
        pendingStart = nil
        let duration = Self.finiteDuration(player.currentItem?.duration.seconds)
        if let duration, start >= duration { return }
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
    }

    private func handleDidPlayToEnd() {
        if let channel = state.channel, channel.kind != .live,
           let duration = Self.finiteDuration(player.currentItem?.duration.seconds) {
            CatalogModel.shared.recordProgress(channelID: channel.id, position: duration, duration: duration)
        }
        pause()
    }

    /// Records the current position of an on-demand item (before switching, pausing or stopping).
    private func saveProgressOfCurrentItem() {
        guard pendingStart == nil, let channel = state.channel, channel.kind != .live,
              let item = player.currentItem else { return }
        let position = item.currentTime().seconds
        guard position.isFinite else { return }
        CatalogModel.shared.recordProgress(
            channelID: channel.id, position: position, duration: Self.finiteDuration(item.duration.seconds)
        )
    }

    // MARK: Reconnection (live streams)

    /// Schedules a replay of the current live stream. Returns `false` when retries are used up.
    private func scheduleReconnect() -> Bool {
        guard state.isLive, let request = currentRequest, let channelID = state.channel?.id,
              let delay = reconnect.noteFailure(at: Date()) else { return false }
        state.reconnectAttempt = reconnect.attempt
        state.markBuffering()
        publishNowPlaying()
        log.info("Live stream dropped; reconnecting (attempt \(self.reconnect.attempt, privacy: .public))")
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.state.channel?.id == channelID else { return }
            self.reconnectTask = nil
            self.load(request)
        }
        return true
    }

    private func startStallTimerIfLive() {
        guard state.isLive, stallTask == nil else { return }
        stallTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ReconnectPolicy.stallTimeout * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.stallTask = nil
            guard self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate, self.state.isLive else { return }
            // Reconnects while retries remain, otherwise reports the stall as a failure.
            self.handleFailure(CarMediaError.transport("stalled"))
        }
    }

    private func cancelStallTimer() {
        stallTask?.cancel()
        stallTask = nil
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        cancelStallTimer()
        state.reconnectAttempt = nil
    }

    private static func finiteDuration(_ seconds: Double?) -> Double? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    private func handleFailure(_ error: Error?) {
        guard state.isActive, !state.isFailed else { return }
        cancelStallTimer()
        if scheduleReconnect() { return }
        if let error {
            state.fail(error, secrets: secrets)
            let detail = UserFacingError.redactedDetail(of: error, secrets: secrets)
            log.error("Playback failed: \(detail, privacy: .private)")
        } else {
            state.fail(.unknown)
        }
        player.pause()
        deactivateSession()
        publishNowPlaying()
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            state.markPaused()
            isSessionActive = false
            publishNowPlaying()
        case .ended:
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume), state.isActive {
                resume()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        // Headphones unplugged or CarPlay disconnected: pause instead of blasting the phone speaker.
        if reason == .oldDeviceUnavailable, state.isPlaying {
            pause()
        }
    }

    // MARK: Audio session

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        if isSessionActive {
            // Switching between radio and video keeps the session active; only the policy may change.
            if session.routeSharingPolicy != sessionPolicy {
                try? session.setCategory(.playback, mode: .default, policy: sessionPolicy, options: [])
            }
            return
        }
        do {
            try session.setCategory(.playback, mode: .default, policy: sessionPolicy, options: [])
            try session.setActive(true)
            isSessionActive = true
        } catch {
            log.error("Audio session activation failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func deactivateSession() {
        guard isSessionActive else { return }
        isSessionActive = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log.error("Audio session deactivation failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Now Playing

    private func publishNowPlaying() {
        nowPlaying.update(state, artwork: artwork)
    }

    private func loadArtwork(for channel: Channel) {
        guard let url = channel.logoURL else { return }
        Task {
            let image = await ImageLoader.shared.image(for: url, maxPixelSize: 300)
            guard state.channel?.id == channel.id else { return }
            artwork = image
            publishNowPlaying()
        }
    }

    private func xtreamSecrets(sourceID: String?) -> [String] {
        guard let sourceID, let password = try? AppModel.shared.credentials.password(forSourceID: sourceID) else {
            return []
        }
        return [password]
    }
}
