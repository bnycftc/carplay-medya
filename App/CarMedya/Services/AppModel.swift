import CarMediaCore
import CarMediaKit
import Foundation
import os

/// App-wide state shared by the phone UI and the CarPlay scene.
///
/// Sources are owned by an ``InMemorySourceStore`` (actor) and persisted as JSON in Application Support.
/// Xtream passwords live only in the Keychain; Xtream channel lists are re-fetched on launch.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    /// Sources in display order.
    @Published private(set) var records: [SourceRecord] = []
    /// Channels, groups, favorites and recents of all sources.
    @Published private(set) var library = LibraryState()
    /// Programme guides keyed by source id.
    @Published private(set) var guides: [String: EPGStore] = [:]
    /// Sources currently being refreshed.
    @Published private(set) var refreshingSourceIDs: Set<String> = []

    let credentials: KeychainStore
    private let store: InMemorySourceStore
    private let provider: DefaultPlaylistProvider
    private let sourcesFile: SnapshotFile<SourceStoreSnapshot>
    private let preferencesFile: SnapshotFile<LibraryPreferences>
    private let importsDirectory: URL
    private let writer = SnapshotWriter()
    private let presenter = EPGPresenter()
    private var saveGeneration = 0
    private var didStart = false
    /// Sources of playables that are not in the channel library (movies, episodes, archive programmes).
    private var playableSources: [String: String] = [:]
    private let log = Logger(subsystem: "com.bnycftc.carmedya", category: "sources")

    /// Sources older than this are refreshed on launch (Xtream sources are always refreshed).
    private let staleInterval: TimeInterval = 6 * 3600

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CarMedya", isDirectory: true)
        let sources = SnapshotFile<SourceStoreSnapshot>(url: support.appendingPathComponent("sources.json"))
        let preferencesFile = SnapshotFile<LibraryPreferences>(url: support.appendingPathComponent("library.json"))
        let keychain = KeychainStore()
        self.sourcesFile = sources
        self.preferencesFile = preferencesFile
        self.credentials = keychain
        importsDirectory = support.appendingPathComponent("Imports", isDirectory: true)

        // A corrupt file falls back to an empty state rather than crashing.
        let snapshot: SourceStoreSnapshot = (try? sources.load()) ?? SourceStoreSnapshot.empty
        let preferences: LibraryPreferences = (try? preferencesFile.load()) ?? LibraryPreferences()

        let provider = DefaultPlaylistProvider(credentials: keychain, resolveBookmark: { data in
            var isStale = false
            return try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        }, inflateGzip: { data in
            try GzipInflater.inflate(data)
        })
        self.provider = provider
        store = InMemorySourceStore(snapshot: snapshot, provider: provider)

        records = snapshot.records
        var initial = LibraryState(preferences: preferences)
        initial.setContent(snapshot.records.compactMap { record in
            snapshot.playlists[record.id].map { (id: record.id, name: record.source.name, playlist: $0) }
        })
        library = initial
    }

    // MARK: Lifecycle

    /// Refreshes stale sources once per launch. Safe to call from both scenes.
    func start() {
        guard !didStart else { return }
        didStart = true
        Task { await refreshAll(force: false) }
    }

    /// Refreshes all sources (or only stale ones and Xtream accounts when `force` is `false`).
    func refreshAll(force: Bool) async {
        let now = Date()
        let due = records.filter { record in
            if force || record.source.isXtream { return true }
            guard let last = record.lastRefreshedAt else { return true }
            return now.timeIntervalSince(last) > staleInterval
        }
        await withTaskGroup(of: Void.self) { group in
            for record in due {
                group.addTask { await self.refresh(sourceID: record.id) }
            }
        }
        // Guides of sources that were not refreshed (cached playlists) still need loading.
        for record in records where guides[record.id] == nil && !due.contains(where: { $0.id == record.id }) {
            if let playlist = await store.playlist(forSourceID: record.id) {
                await loadGuide(for: record, playlist: playlist)
            }
        }
    }

    /// Reloads one source, then its guide.
    func refresh(sourceID: String) async {
        guard !refreshingSourceIDs.contains(sourceID) else { return }
        refreshingSourceIDs.insert(sourceID)
        defer { refreshingSourceIDs.remove(sourceID) }
        do {
            let playlist = try await store.refresh(sourceID: sourceID)
            await reloadFromStore()
            if let record = records.first(where: { $0.id == sourceID }) {
                await loadGuide(for: record, playlist: playlist)
            }
        } catch {
            log.error("Refresh failed: \(String(describing: UserFacingError.from(error)), privacy: .public)")
            await reloadFromStore()
        }
    }

    // MARK: Adding and removing sources

    /// Adds an M3U list and loads it.
    func addM3U(name: String, urlText: String, userAgent: String?) async throws {
        let source = try SourceDraft.m3uSource(name: name, urlText: urlText, userAgent: userAgent)
        try await add(source)
    }

    /// Stores the password in the Keychain, adds the account and loads it.
    func addXtream(name: String, credentials xtream: XtreamCredentials) async throws {
        let source = SourceDraft.xtreamSource(name: name, credentials: xtream)
        try credentials.setPassword(xtream.password, forSourceID: source.id)
        do {
            try await add(source)
        } catch {
            try? credentials.removePassword(forSourceID: source.id)
            throw error
        }
    }

    /// Copies a file picked with `.fileImporter` into the app container and adds it as a source.
    func importFile(at pickedURL: URL) async throws {
        let id = SourceDraft.makeID()
        let directory = importsDirectory
        let destination: URL = try await Task.detached(priority: .userInitiated) {
            let access = pickedURL.startAccessingSecurityScopedResource()
            defer { if access { pickedURL.stopAccessingSecurityScopedResource() } }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var target = directory.appendingPathComponent(id).appendingPathExtension(pickedURL.pathExtension)
            try FileManager.default.copyItem(at: pickedURL, to: target)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? target.setResourceValues(values)
            return target
        }.value
        do {
            let bookmark = try destination.bookmarkData()
            try await add(SourceDraft.localFileSource(id: id, fileName: pickedURL.lastPathComponent, bookmark: bookmark))
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Removes a source, its Keychain password and any imported file.
    func remove(sourceID: String) async {
        guard let record = records.first(where: { $0.id == sourceID }) else { return }
        switch record.source {
        case .xtream:
            try? credentials.removePassword(forSourceID: sourceID)
        case .localFile(_, _, let bookmark):
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale),
               url.standardizedFileURL.path.hasPrefix(importsDirectory.standardizedFileURL.path) {
                try? FileManager.default.removeItem(at: url)
            }
        case .m3uURL:
            break
        }
        await store.remove(sourceID: sourceID)
        guides[sourceID] = nil
        playableSources = playableSources.filter { $0.value != sourceID }
        CatalogModel.shared.forget(sourceID: sourceID)
        await reloadFromStore()
    }

    /// Renames a source.
    func rename(sourceID: String, to name: String) async {
        try? await store.rename(sourceID: sourceID, to: name)
        await reloadFromStore()
    }

    /// Runs the Xtream "connection test".
    func testXtream(_ xtream: XtreamCredentials) async throws -> XtreamAccountSummary {
        let info = try await XtreamClient(credentials: xtream).accountInfo()
        return XtreamAccountSummary(info: info)
    }

    private func add(_ source: MediaSource) async throws {
        try await store.add(source)
        await reloadFromStore()
        await refresh(sourceID: source.id)
    }

    // MARK: Favorites and recents

    func isFavorite(_ channelID: String) -> Bool { library.isFavorite(channelID) }

    func toggleFavorite(_ channelID: String) {
        library.toggleFavorite(channelID)
        savePreferences()
    }

    func moveFavorite(from source: Int, to destination: Int) {
        library.moveFavorite(from: source, to: destination)
        savePreferences()
    }

    /// Remembers which source a movie, episode or archive programme came from (not in the library).
    func registerPlayable(_ channelID: String, sourceID: String) {
        playableSources[channelID] = sourceID
    }

    /// An Xtream client for `sourceID` with the password from the Keychain.
    func xtreamClient(sourceID: String) throws -> XtreamClient {
        guard let record = records.first(where: { $0.id == sourceID }),
              case .xtream(let id, _, let account) = record.source else {
            throw SourceStoreError.unknownSource
        }
        return try provider.xtreamClient(sourceID: id, account: account)
    }

    func recordPlayed(_ channelID: String) {
        library.recordPlayed(channelID)
        savePreferences()
    }

    func clearRecents() {
        library.clearRecents()
        savePreferences()
    }

    // MARK: Lookups used by playback and CarPlay

    /// The source record a channel belongs to.
    func record(forChannelID channelID: String) -> SourceRecord? {
        guard let sourceID = library.sourceID(forChannelID: channelID) ?? playableSources[channelID] else { return nil }
        return records.first { $0.id == sourceID }
    }

    /// The programme guide of the source a channel belongs to.
    func guide(for channel: Channel) -> EPGStore? {
        guard let sourceID = library.sourceID(forChannelID: channel.id) else { return nil }
        return guides[sourceID]
    }

    /// "Now / next" for a channel, if its source has a guide.
    func epgSummary(for channel: Channel, at date: Date) -> EPGSummary? {
        guard let sourceID = library.sourceID(forChannelID: channel.id), let guide = guides[sourceID] else { return nil }
        return presenter.summary(for: channel, in: guide, at: date)
    }

    // MARK: Internals

    private func loadGuide(for record: SourceRecord, playlist: Playlist) async {
        do {
            guides[record.id] = try await provider.loadGuide(for: record.source, playlist: playlist)
        } catch {
            // Guides are optional; keep the previous one.
            log.info("Guide unavailable: \(String(describing: UserFacingError.from(error)), privacy: .public)")
        }
    }

    /// Pulls records and playlists from the store and rebuilds the library off the main thread.
    private func reloadFromStore() async {
        let newRecords = await store.records()
        var content: [(id: String, name: String, playlist: Playlist)] = []
        for record in newRecords {
            if let playlist = await store.playlist(forSourceID: record.id) {
                content.append((id: record.id, name: record.source.name, playlist: playlist))
            }
        }
        let seed = library.preferences
        let sources = content
        var rebuilt = await Task.detached(priority: .userInitiated) { () -> LibraryState in
            var state = LibraryState(preferences: seed)
            state.setContent(sources)
            return state
        }.value
        // Favorites may have changed while rebuilding.
        rebuilt.setPreferences(library.preferences)
        records = newRecords
        library = rebuilt
        saveSources()
    }

    private func savePreferences() {
        do {
            try preferencesFile.save(library.preferences)
        } catch {
            log.error("Saving preferences failed")
        }
    }

    private func saveSources() {
        saveGeneration += 1
        let generation = saveGeneration
        let file = sourcesFile
        let store = self.store
        let writer = self.writer
        Task.detached(priority: .utility) {
            let snapshot = await store.snapshot()
            await writer.write(snapshot, generation: generation, to: file)
        }
    }
}

/// Serializes snapshot writes and drops out-of-order (older) ones.
private actor SnapshotWriter {
    private var lastWritten = 0

    func write(_ snapshot: SourceStoreSnapshot, generation: Int, to file: SnapshotFile<SourceStoreSnapshot>) {
        guard generation > lastWritten else { return }
        lastWritten = generation
        try? file.save(snapshot)
    }
}
