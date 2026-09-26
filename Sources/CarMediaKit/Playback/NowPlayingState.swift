import Foundation
import CarMediaCore

/// UI-independent state of the player, shared by the phone UI, lock screen and CarPlay.
public struct NowPlayingState: Sendable, Equatable {
    /// Playback phase.
    public enum Phase: Sendable, Equatable {
        /// Nothing loaded.
        case idle
        /// Opening or buffering.
        case loading
        /// Playing.
        case playing
        /// Paused by the user or an interruption.
        case paused
        /// Failed; `detail` is already redacted.
        case failed(UserFacingError, detail: String?)
    }

    /// Current channel.
    public private(set) var channel: Channel?
    /// The list the channel was started from (used for next/previous).
    public private(set) var queue: [Channel] = []
    /// Current phase.
    public private(set) var phase: Phase = .idle
    /// `true` for live streams.
    public private(set) var isLive = false
    /// `true` for audio-only content.
    public private(set) var isAudioOnly = false
    /// Elapsed seconds (on-demand content only).
    public private(set) var elapsed: TimeInterval = 0
    /// Duration in seconds, when known (never for live streams).
    public private(set) var duration: TimeInterval?
    /// Title of the programme on air (from the guide), shown as subtitle.
    public var programmeTitle: String?
    /// Automatic reconnection in progress: attempt number (1…3), or `nil`.
    public var reconnectAttempt: Int?

    /// Creates an idle state.
    public init() {}

    // MARK: Transitions

    /// Starts loading `channel`, remembering the list it came from.
    public mutating func begin(_ channel: Channel, request: PlaybackRequest, queue: [Channel] = []) {
        self.channel = channel
        self.queue = queue.contains(where: { $0.id == channel.id }) ? queue : [channel]
        phase = .loading
        isLive = request.isLive
        isAudioOnly = request.isAudioOnly
        elapsed = 0
        duration = nil
        programmeTitle = nil
        reconnectAttempt = nil
    }

    /// Selects `channel` but records that it cannot be played, so the UI can say why.
    public mutating func reject(_ channel: Channel, reason: UnsupportedReason, queue: [Channel] = []) {
        self = NowPlayingState()
        self.channel = channel
        self.queue = queue.contains(where: { $0.id == channel.id }) ? queue : [channel]
        isLive = channel.kind == .live
        isAudioOnly = channel.isRadio
        phase = .failed(.unsupported(reason), detail: nil)
    }

    /// Marks playback as running.
    public mutating func markPlaying() {
        guard channel != nil else { return }
        phase = .playing
    }

    /// Marks playback as buffering (only while a channel is active and not failed).
    public mutating func markBuffering() {
        guard channel != nil, !isFailed else { return }
        phase = .loading
    }

    /// Marks playback as paused.
    public mutating func markPaused() {
        guard channel != nil, !isFailed else { return }
        phase = .paused
    }

    /// Records a failure. Pass every secret that could appear in `error` (e.g. the Xtream password).
    public mutating func fail(_ error: Error, secrets: [String]) {
        phase = .failed(UserFacingError.from(error), detail: UserFacingError.redactedDetail(of: error, secrets: secrets))
    }

    /// Records a failure that has no underlying error (e.g. an unsupported format).
    public mutating func fail(_ kind: UserFacingError) {
        phase = .failed(kind, detail: nil)
    }

    /// Updates the playhead. Ignored for live streams; invalid values are dropped.
    public mutating func updateTime(elapsed: TimeInterval, duration: TimeInterval?) {
        guard !isLive else { return }
        if elapsed.isFinite, elapsed >= 0 { self.elapsed = elapsed }
        if let duration, duration.isFinite, duration > 0 { self.duration = duration } else { self.duration = nil }
    }

    /// Returns to idle.
    public mutating func stop() {
        self = NowPlayingState()
    }

    // MARK: Derived

    /// Whether a channel is loaded (in any phase except idle).
    public var isActive: Bool { channel != nil }

    /// Whether the phase is `.playing`.
    public var isPlaying: Bool { phase == .playing }

    /// Whether the phase is `.failed`.
    public var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    /// The failure classification, if failed.
    public var failure: UserFacingError? {
        if case .failed(let kind, _) = phase { return kind }
        return nil
    }

    /// Seeking makes sense only for on-demand content with a known duration.
    public var canSeek: Bool { !isLive && duration != nil }

    /// Fraction played (`0...1`), `nil` for live or unknown duration.
    public var progress: Double? {
        guard !isLive, let duration, duration > 0 else { return nil }
        return min(1, max(0, elapsed / duration))
    }

    /// Main title line.
    public var title: String { channel?.title ?? "" }

    /// Secondary line: programme on air, else the channel group.
    public var subtitle: String? { programmeTitle ?? channel?.groupTitle }

    /// The channel after the current one in the queue (wrapping around), if the queue has more than one.
    public var nextChannel: Channel? { neighbor(offset: 1) }

    /// The channel before the current one in the queue (wrapping around).
    public var previousChannel: Channel? { neighbor(offset: -1) }

    /// The channel after the current one in the queue, or `nil` at the end (no wrap-around).
    public var nextChannelWithoutWrap: Channel? {
        guard let channel, let index = queue.firstIndex(where: { $0.id == channel.id }),
              index + 1 < queue.count else { return nil }
        return queue[index + 1]
    }

    private func neighbor(offset: Int) -> Channel? {
        guard let channel, queue.count > 1, let index = queue.firstIndex(where: { $0.id == channel.id }) else {
            return nil
        }
        let next = (index + offset + queue.count) % queue.count
        return queue[next]
    }
}
