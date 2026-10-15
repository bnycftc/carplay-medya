import CarMediaCore
import CarMediaKit
import CarPlay
import Combine
import CoreMedia
import UIKit

/// CarPlay audio scene: Favoriler / Kanallar / A–Z / Son Oynatılan tabs and the shared Now Playing template.
///
/// Everything works without touching the phone: lists come from ``AppModel`` (loaded at launch even
/// if only CarPlay is connected), selecting an item starts playback and pushes Now Playing.
/// This is a CarPlay audio app (`carplay-audio` only). On iOS 27, in vehicles that support video in
/// the car, rows carry a `CPPlaybackConfiguration` so the system can present the video (AirPlay video,
/// only while parked; the car enforces it). Everywhere else the rows and behaviour are unchanged.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPSessionConfigurationDelegate {
    /// A playable list row, tracked weakly so its playback configuration can be refreshed in place.
    private final class PlayableRow {
        weak var item: CPListItem?
        let channel: Channel

        init(item: CPListItem, channel: Channel) {
            self.item = item
            self.channel = channel
        }
    }

    private var interfaceController: CPInterfaceController?
    /// Named differently from the delegate methods so `sessionConfig` never resolves to an overload.
    private var sessionConfig: CPSessionConfiguration?
    private var favoritesTemplate: CPListTemplate?
    private var channelsTemplate: CPListTemplate?
    private var recentsTemplate: CPListTemplate?
    private var alphabetTemplate: CPListTemplate?
    private var cancellables = Set<AnyCancellable>()
    private var lastAlertedFailure: String?
    private var playableRows: [PlayableRow] = []
    private let resolver = PlaybackURLResolver()

    // MARK: CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        MotionMonitor.shared.setCarPlayConnected(true)
        AppModel.shared.start()
        sessionConfig = CPSessionConfiguration(delegate: self)
        let carSupportsVideo = carSupportsVideoNow
        CarVideoDiagnostics.shared.recordConnect(systemSupportsAPI: carSupportsVideo != nil, carSupportsVideo: carSupportsVideo)
        configureNowPlayingTemplate()

        let favorites = makeListTemplate(
            title: String(localized: "Favoriler"),
            systemImage: "star.fill",
            emptyTitle: String(localized: "Favori kanal yok")
        )
        let channels = makeListTemplate(
            title: String(localized: "Kanallar"),
            systemImage: "list.bullet",
            emptyTitle: String(localized: "Kanal yok")
        )
        let recents = makeListTemplate(
            title: String(localized: "Son Oynatılan"),
            systemImage: "clock",
            emptyTitle: String(localized: "Henüz bir şey oynatılmadı")
        )
        let alphabet = makeListTemplate(
            title: String(localized: "A–Z"),
            systemImage: "textformat.abc",
            emptyTitle: String(localized: "Kanal yok")
        )
        favoritesTemplate = favorites
        channelsTemplate = channels
        recentsTemplate = recents
        alphabetTemplate = alphabet

        // Audio apps get at most four tabs; finding a channel by letter replaces keyboard search,
        // which CarPlay audio apps do not have (voice search goes through Siri, see PlaybackIntents).
        // No extra tab for video: audio apps get four tabs (CarPlay Developer Guide); video plays from the existing rows.
        let tabs: [CPTemplate] = [favorites, channels, alphabet, recents]
        let tabBar = CPTabBarTemplate(templates: tabs)
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)

        observeModel()
        reloadAll(library: AppModel.shared.library)
        // `supportsVideoPlayback` may not be final when the rows are first built and has no change callback:
        // read it again shortly after connecting so the first tap already gets the video row.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.refreshPlaybackConfigurations()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        cancellables.removeAll()
        self.interfaceController = nil
        sessionConfig = nil
        playableRows.removeAll()
        favoritesTemplate = nil
        channelsTemplate = nil
        recentsTemplate = nil
        alphabetTemplate = nil
        MotionMonitor.shared.setCarPlayConnected(false)
        CarVideoDiagnostics.shared.recordDisconnect()
    }

    // MARK: CPSessionConfigurationDelegate

    func sessionConfiguration(
        _ sessionConfiguration: CPSessionConfiguration,
        limitedUserInterfacesChanged limitedUserInterfaces: CPLimitableUserInterface
    ) {
        // CarPlay has no callback for `supportsVideoPlayback` itself; any configuration change re-reads it.
        refreshPlaybackConfigurations()
    }

    func sessionConfiguration(
        _ sessionConfiguration: CPSessionConfiguration,
        contentStyleChanged contentStyle: CPContentStyle
    ) {
        // CarPlay has no callback for `supportsVideoPlayback` itself; any configuration change re-reads it.
        refreshPlaybackConfigurations()
    }

    // MARK: Templates

    private func makeListTemplate(title: String, systemImage: String, emptyTitle: String) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: [])
        template.tabTitle = title
        template.tabImage = UIImage(systemName: systemImage)
        template.emptyViewTitleVariants = [emptyTitle]
        return template
    }

    private func configureNowPlayingTemplate() {
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.isUpNextButtonEnabled = false
        nowPlaying.isAlbumArtistButtonEnabled = false
        let favoriteButton = CPNowPlayingAddToLibraryButton { _ in
            guard let channel = PlaybackController.shared.state.channel else { return }
            AppModel.shared.toggleFavorite(channel.id)
        }
        nowPlaying.updateNowPlayingButtons([favoriteButton])
    }

    private func observeModel() {
        cancellables.removeAll()
        // @Published emits the new value before the property changes, so use the emitted value.
        AppModel.shared.$library
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] library in self?.reloadAll(library: library) }
            .store(in: &cancellables)

        PlaybackController.shared.$state
            .map { $0.channel?.id }
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadAll(library: AppModel.shared.library) }
            .store(in: &cancellables)

        PlaybackController.shared.$state
            .map { state -> String? in
                guard let failure = state.failure, let id = state.channel?.id else { return nil }
                return id + "|" + failure.message
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] key in self?.handleFailureChange(key) }
            .store(in: &cancellables)

        // Row play/pause state follows playback (update the playback configuration on every state change).
        // The emitted value precedes the property change; after the debounce the property is current.
        PlaybackController.shared.$state
            .map { state -> (String?, Bool) in
                (state.channel?.id, state.isPlaying || state.phase == .loading)
            }
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshPlaybackConfigurations() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ -> Bool in
                UserDefaults.standard.object(forKey: SettingsKeys.carVideoEnabled) as? Bool ?? false
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshPlaybackConfigurations() }
            .store(in: &cancellables)
    }

    private func reloadAll(library: LibraryState) {
        let maxItems = CPListTemplate.maximumItemCount
        let maxSections = CPListTemplate.maximumSectionCount

        let favorites = ListCapping.cap(library.favorites, maxItems: maxItems)
        favoritesTemplate?.updateSections([CPListSection(items: favorites.map { makeItem($0, queue: favorites) })])

        let recents = ListCapping.cap(library.recents, maxItems: maxItems)
        recentsTemplate?.updateSections([CPListSection(items: recents.map { makeItem($0, queue: recents) })])

        // Kanallar: one section per source, one row per group (drill down to channels).
        let sections = library.visibleSections.map { section in
            ListSection(header: section.title, items: section.groups)
        }
        let capped = ListCapping.cap(sections, maxSections: maxSections, maxItems: maxItems)
        let showHeaders = capped.sections.count > 1
        channelsTemplate?.updateSections(capped.sections.map { section in
            CPListSection(
                items: section.items.map { makeGroupItem($0, library: library) },
                header: showHeaders ? section.header : nil,
                sectionIndexTitle: nil
            )
        })

        reloadAlphabet(library: library)
        // Pushed group/letter templates keep their rows, so only drop rows that no longer exist.
        playableRows.removeAll { $0.item == nil }
    }

    /// A–Z tab: one row per letter; a letter opens its channels (capped to the car's list limit).
    private func reloadAlphabet(library: LibraryState) {
        let buckets = AlphabetIndex.buckets(library.visibleChannels)
        let rows = ListCapping.cap(buckets, maxItems: CPListTemplate.maximumItemCount)
        alphabetTemplate?.updateSections([CPListSection(items: rows.map { bucket in
            let item = CPListItem(text: bucket.letter, detailText: String(localized: "\(bucket.channels.count) kanal"))
            item.accessoryType = .disclosureIndicator
            let letter = bucket.letter
            item.handler = { [weak self] _, completion in
                self?.showLetter(letter)
                completion()
            }
            return item
        })])
    }

    private func showLetter(_ letter: String) {
        guard let interfaceController else { return }
        let bucket = AlphabetIndex.buckets(AppModel.shared.library.visibleChannels).first { $0.letter == letter }
        let channels = ListCapping.cap(bucket?.channels ?? [], maxItems: CPListTemplate.maximumItemCount)
        let template = CPListTemplate(
            title: letter,
            sections: [CPListSection(items: channels.map { makeItem($0, queue: channels) })]
        )
        template.emptyViewTitleVariants = [String(localized: "Kanal yok")]
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    private func makeGroupItem(_ group: LibraryGroup, library: LibraryState) -> CPListItem {
        let title = group.name ?? String(localized: "Diğer")
        let item = CPListItem(text: title, detailText: String(localized: "\(group.count) kanal"), image: nil)
        item.accessoryType = .disclosureIndicator
        let groupID = group.id
        item.handler = { [weak self] _, completion in
            self?.showGroup(id: groupID)
            completion()
        }
        return item
    }

    private func showGroup(id: String) {
        let library = AppModel.shared.library
        guard let interfaceController, let group = library.group(id: id) else { return }
        let channels = ListCapping.cap(library.channels(in: group), maxItems: CPListTemplate.maximumItemCount)
        let template = CPListTemplate(
            title: group.name ?? String(localized: "Diğer"),
            sections: [CPListSection(items: channels.map { makeItem($0, queue: channels) })]
        )
        template.emptyViewTitleVariants = [String(localized: "Kanal yok")]
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    private func makeItem(_ channel: Channel, queue: [Channel]) -> CPListItem {
        let summary = AppModel.shared.epgSummary(for: channel, at: Date())
        let detail = summary?.now?.title ?? channel.groupTitle
        let item = CPListItem(text: channel.title, detailText: detail, image: ArtworkRenderer.artwork(logo: nil, title: channel.title, side: Self.itemImageSide))
        item.isPlaying = PlaybackController.shared.state.channel?.id == channel.id
        item.handler = { [weak self] _, completion in
            self?.select(channel, queue: queue)
            completion()
        }
        loadLogo(for: channel, into: item)
        playableRows.append(PlayableRow(item: item, channel: channel))
        applyPlaybackConfiguration(
            to: item, channel: channel, policy: presentationPolicy, state: PlaybackController.shared.state
        )
        return item
    }

    /// `CPSessionConfiguration.supportsVideoPlayback` right now; nil before iOS 27 or without a session.
    private var carSupportsVideoNow: Bool? {
        guard #available(iOS 27, *), let config = sessionConfig else { return nil }
        return config.supportsVideoPlayback
    }

    /// Whether the connected car supports video (iOS 27 only) and the user allows it (Settings).
    /// `supportsVideoPlayback` is re-read on every refresh (playback state / settings change / session
    /// configuration callbacks / 2 s after connecting); CarPlay offers no callback for the property itself.
    private var presentationPolicy: CarPresentationPolicy {
        let carSupportsVideo: Bool = carSupportsVideoNow ?? false
        // Off unless the user turns on "Park halinde araç ekranında video" (bny, 2026-10-15).
        let userAllowsVideoInCar = UserDefaults.standard.object(forKey: SettingsKeys.carVideoEnabled) as? Bool ?? false
        return CarPresentationPolicy(carSupportsVideo: carSupportsVideo, userAllowsVideoInCar: userAllowsVideoInCar)
    }

    /// Marks `item` for the system's video presentation (iOS 27, video-capable cars); otherwise leaves it plain.
    /// `CPListItem.playbackConfiguration` is `@NSCopying`, so a new object is assigned on every change.
    private func applyPlaybackConfiguration(
        to item: CPListItem,
        channel: Channel,
        policy: CarPresentationPolicy,
        state: NowPlayingState
    ) {
        guard #available(iOS 27, *) else { return }
        // Without video the rows stay plain (no write at all, so cars without video see 0.6.1 behaviour).
        guard policy.videoAvailable else {
            if item.playbackConfiguration != nil { item.playbackConfiguration = nil }
            return
        }
        let isXtream = AppModel.shared.record(forChannelID: channel.id)?.source.isXtream ?? false
        guard let isAudioOnly = resolver.isAudioOnly(channel, isXtreamSource: isXtream) else {
            if item.playbackConfiguration != nil { item.playbackConfiguration = nil }
            return
        }
        let isCurrent = state.channel?.id == channel.id
        let isActive = state.isPlaying || state.phase == .loading
        item.playbackConfiguration = CPPlaybackConfiguration(
            preferredPresentation: policy.presentation(isAudioOnly: isAudioOnly) == .video ? .video : .audio,
            playbackAction: CarPresentationPolicy.rowAction(isCurrent: isCurrent, isActive: isActive) == .pause ? .pause : .play,
            elapsedTime: .zero,
            duration: .zero
        )
    }

    /// Re-applies the playback configuration to every live row with the current playback state.
    private func refreshPlaybackConfigurations() {
        if let carSupportsVideo = carSupportsVideoNow {
            CarVideoDiagnostics.shared.recordSample(carSupportsVideo: carSupportsVideo)
        }
        playableRows.removeAll { $0.item == nil }
        let policy = presentationPolicy
        let state = PlaybackController.shared.state
        for row in playableRows {
            guard let item = row.item else { continue }
            applyPlaybackConfiguration(to: item, channel: row.channel, policy: policy, state: state)
        }
    }

    private func loadLogo(for channel: Channel, into item: CPListItem) {
        guard let url = channel.logoURL else { return }
        let title = channel.title
        if let cached = ImageLoader.shared.cachedImage(for: url) {
            item.setImage(ArtworkRenderer.artwork(logo: cached, title: title, side: Self.itemImageSide))
            return
        }
        let side = max(CPListItem.maximumImageSize.width, CPListItem.maximumImageSize.height)
        Task { [weak item] in
            guard let image = await ImageLoader.shared.image(for: url, maxPixelSize: side) else { return }
            item?.setImage(ArtworkRenderer.artwork(logo: image, title: title, side: Self.itemImageSide))
        }
    }

    /// List row artwork in pixels (rendered at scale 1): the largest CarPlay row image at 3×.
    private static var itemImageSide: CGFloat {
        max(CPListItem.maximumImageSize.width, CPListItem.maximumImageSize.height) * 3
    }

    // MARK: Playback

    /// Row selection. With video available the row acts as play/pause for the current channel
    /// (matching the row's `playbackAction`); otherwise it always starts playback as before.
    private func select(_ channel: Channel, queue: [Channel]) {
        guard presentationPolicy.videoAvailable else {
            play(channel, queue: queue)
            return
        }
        let state = PlaybackController.shared.state
        let intent = CarPresentationPolicy.tapIntent(
            isCurrent: state.channel?.id == channel.id,
            isActive: state.isPlaying || state.phase == .loading,
            isPaused: state.phase == .paused
        )
        switch intent {
        case .pause:
            PlaybackController.shared.pause()
        case .resume:
            noteVideoAttempt(channel)
            PlaybackController.shared.resume()
            if let interfaceController, !PlaybackController.shared.state.isFailed,
               interfaceController.topTemplate !== CPNowPlayingTemplate.shared {
                interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
            }
        case .start:
            play(channel, queue: queue)
        }
    }

    private func play(_ channel: Channel, queue: [Channel]) {
        noteVideoAttempt(channel)
        PlaybackController.shared.play(channel, queue: queue, presentPlayer: false)
        guard let interfaceController else { return }
        if !PlaybackController.shared.state.isFailed, interfaceController.topTemplate !== CPNowPlayingTemplate.shared {
            interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
        }
    }

    /// Diagnostics (Settings > "Araç ekranında video"): records that a row marked `.video` was played.
    private func noteVideoAttempt(_ channel: Channel) {
        let isXtream = AppModel.shared.record(forChannelID: channel.id)?.source.isXtream ?? false
        guard let isAudioOnly = resolver.isAudioOnly(channel, isXtreamSource: isXtream) else { return }
        if presentationPolicy.presentation(isAudioOnly: isAudioOnly) == .video {
            CarVideoDiagnostics.shared.recordVideoPlay()
        }
    }

    private func handleFailureChange(_ key: String?) {
        guard let key else {
            lastAlertedFailure = nil
            return
        }
        guard key != lastAlertedFailure, let interfaceController,
              let failure = PlaybackController.shared.state.failure else { return }
        lastAlertedFailure = key
        let dismiss = CPAlertAction(title: String(localized: "Tamam"), style: .cancel) { [weak interfaceController] _ in
            interfaceController?.dismissTemplate(animated: true, completion: nil)
        }
        let alert = CPAlertTemplate(titleVariants: [failure.message], actions: [dismiss])
        if interfaceController.presentedTemplate != nil {
            // Only one presented template is allowed at a time; wait for the dismissal to finish.
            interfaceController.dismissTemplate(animated: false) { [weak interfaceController] _, _ in
                interfaceController?.presentTemplate(alert, animated: true, completion: nil)
            }
        } else {
            interfaceController.presentTemplate(alert, animated: true, completion: nil)
        }
    }
}
