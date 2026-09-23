import CarMediaCore
import CarMediaKit
import CarPlay
import Combine
import UIKit

/// CarPlay audio scene: Favoriler / Kanallar / Son Oynatılan tabs and the shared Now Playing template.
///
/// Everything works without touching the phone: lists come from ``AppModel`` (loaded at launch even
/// if only CarPlay is connected), selecting an item starts playback and pushes Now Playing.
/// Video is never shown here; CarPlay video (iOS 27) is v1.1.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var favoritesTemplate: CPListTemplate?
    private var channelsTemplate: CPListTemplate?
    private var recentsTemplate: CPListTemplate?
    private var cancellables = Set<AnyCancellable>()
    private var lastAlertedFailure: String?

    // MARK: CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        MotionMonitor.shared.setCarPlayConnected(true)
        AppModel.shared.start()
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
        favoritesTemplate = favorites
        channelsTemplate = channels
        recentsTemplate = recents

        let tabs: [CPTemplate] = [favorites, channels, recents]
        if #available(iOS 27, *) {
            // TODO(v1.1): Search tab for the iOS 27 CarPlay audio/video templates (plan §3 v1.1).
            // Deliberately empty: do not reference iOS 27 CarPlay symbols until they are verified
            // against the released SDK. `CPSearchTemplate` is not available to audio apps.
        }
        let tabBar = CPTabBarTemplate(templates: tabs)
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)

        observeModel()
        reloadAll(library: AppModel.shared.library)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        cancellables.removeAll()
        self.interfaceController = nil
        favoritesTemplate = nil
        channelsTemplate = nil
        recentsTemplate = nil
        MotionMonitor.shared.setCarPlayConnected(false)
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
    }

    private func reloadAll(library: LibraryState) {
        let maxItems = CPListTemplate.maximumItemCount
        let maxSections = CPListTemplate.maximumSectionCount

        let favorites = ListCapping.cap(library.favorites, maxItems: maxItems)
        favoritesTemplate?.updateSections([CPListSection(items: favorites.map { makeItem($0, queue: favorites) })])

        let recents = ListCapping.cap(library.recents, maxItems: maxItems)
        recentsTemplate?.updateSections([CPListSection(items: recents.map { makeItem($0, queue: recents) })])

        // Kanallar: one section per source, one row per group (drill down to channels).
        let sections = library.sections.map { section in
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
        let placeholder = UIImage(systemName: channel.isRadio ? "radio" : "tv")
        let item = CPListItem(text: channel.title, detailText: detail, image: placeholder)
        item.isPlaying = PlaybackController.shared.state.channel?.id == channel.id
        item.handler = { [weak self] _, completion in
            self?.play(channel, queue: queue)
            completion()
        }
        loadLogo(for: channel, into: item)
        return item
    }

    private func loadLogo(for channel: Channel, into item: CPListItem) {
        guard let url = channel.logoURL else { return }
        if let cached = ImageLoader.shared.cachedImage(for: url) {
            item.setImage(cached)
            return
        }
        let side = max(CPListItem.maximumImageSize.width, CPListItem.maximumImageSize.height)
        Task { [weak item] in
            guard let image = await ImageLoader.shared.image(for: url, maxPixelSize: side) else { return }
            item?.setImage(image)
        }
    }

    // MARK: Playback

    private func play(_ channel: Channel, queue: [Channel]) {
        PlaybackController.shared.play(channel, queue: queue, presentPlayer: false)
        guard let interfaceController else { return }
        if !PlaybackController.shared.state.isFailed, interfaceController.topTemplate !== CPNowPlayingTemplate.shared {
            interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
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
