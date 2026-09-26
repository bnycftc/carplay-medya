import AppIntents
import CarMediaCore
import CarMediaKit
import Foundation

/// A channel of the user's own sources, as Siri and Shortcuts see it.
struct ChannelEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Kanal"
    static var defaultQuery = ChannelEntityQuery()

    var id: String
    var title: String
    var group: String?

    var displayRepresentation: DisplayRepresentation {
        if let group {
            return DisplayRepresentation(title: "\(title)", subtitle: "\(group)")
        }
        return DisplayRepresentation(title: "\(title)")
    }

    init(_ channel: Channel) {
        id = channel.id
        title = channel.title
        group = channel.groupTitle
    }
}

/// Finds channels by id, by name (Turkish-aware search) and suggests favorites and recents.
struct ChannelEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [ChannelEntity] {
        await IntentSupport.ensureLibraryLoaded()
        let library = AppModel.shared.library
        return identifiers.compactMap { library.channel(id: $0).map(ChannelEntity.init) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [ChannelEntity] {
        await IntentSupport.ensureLibraryLoaded()
        return AppModel.shared.library.search(string, limit: 20).map(ChannelEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [ChannelEntity] {
        let library = AppModel.shared.library
        var seen = Set<String>()
        let channels = (library.favorites + library.recents).filter { seen.insert($0.id).inserted }
        return channels.prefix(30).map(ChannelEntity.init)
    }
}

/// "CarMedya'da <kanal> aç".
struct PlayChannelIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Kanal oynat"
    static var description = IntentDescription("Kendi kaynaklarınızdaki bir kanalı oynatır.")

    @Parameter(title: "Kanal")
    var channel: ChannelEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$channel) kanalını oynat")
    }

    init() {}

    init(channel: ChannelEntity) {
        self.channel = channel
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await IntentSupport.ensureLibraryLoaded()
        let library = AppModel.shared.library
        guard let found = library.channel(id: channel.id) else {
            return .result(dialog: "Bu kanal artık kaynaklarınızda yok.")
        }
        let queue = library.isFavorite(found.id) ? library.favorites : []
        PlaybackController.shared.play(found, queue: queue, presentPlayer: false)
        return .result(dialog: "\(found.title) açılıyor.")
    }
}

/// "CarMedya'da son kanalı aç": resumes the most recently played channel.
struct PlayLastChannelIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Son kanalı oynat"
    static var description = IntentDescription("En son oynatılan kanalı yeniden açar.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await IntentSupport.ensureLibraryLoaded()
        let library = AppModel.shared.library
        guard let channel = library.recents.first ?? library.favorites.first else {
            return .result(dialog: "Henüz oynatılmış bir kanal yok.")
        }
        PlaybackController.shared.play(channel, queue: library.recents, presentPlayer: false)
        return .result(dialog: "\(channel.title) açılıyor.")
    }
}

/// "CarMedya'yı durdur".
struct StopPlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Oynatmayı durdur"

    @MainActor
    func perform() async throws -> some IntentResult {
        PlaybackController.shared.pause()
        return .result()
    }
}

/// Phrases Siri understands without setup (also in CarPlay).
struct CarMedyaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayChannelIntent(),
            phrases: [
                "\(.applicationName)'da \(\.$channel) aç",
                "\(.applicationName)'da \(\.$channel) oynat",
                "\(.applicationName) ile \(\.$channel) aç",
                "Play \(\.$channel) in \(.applicationName)",
            ],
            shortTitle: "Kanal oynat",
            systemImageName: "play.tv"
        )
        AppShortcut(
            intent: PlayLastChannelIntent(),
            phrases: [
                "\(.applicationName)'da son kanalı aç",
                "\(.applicationName) kaldığım yerden",
                "Resume \(.applicationName)",
            ],
            shortTitle: "Son kanal",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: StopPlaybackIntent(),
            phrases: [
                "\(.applicationName)'yı durdur",
                "Stop \(.applicationName)",
            ],
            shortTitle: "Durdur",
            systemImageName: "stop.fill"
        )
    }
}

@MainActor
enum IntentSupport {
    /// Xtream channel lists are not stored on disk (their URLs contain the password), so a cold launch
    /// from Siri must fetch them before a channel can be found.
    static func ensureLibraryLoaded() async {
        let model = AppModel.shared
        // An Xtream record counts as loaded when its library section has groups.
        let loadedSectionIDs = Set(model.library.sections.filter { !$0.groups.isEmpty }.map(\.id))
        let xtreamIDs = model.records.filter { $0.source.isXtream }.map(\.id)
        let needsXtream = !xtreamIDs.isEmpty && !xtreamIDs.contains { loadedSectionIDs.contains($0) }
        if model.library.isEmpty || needsXtream {
            await model.refreshAll(force: false)
        }
        // A refresh started elsewhere (app launch) returns early above; wait for it, up to 15 s.
        var waited = 0
        while !model.refreshingSourceIDs.isEmpty && waited < 75 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            waited += 1
        }
    }
}
