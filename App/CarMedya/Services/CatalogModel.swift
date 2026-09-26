import CarMediaCore
import CarMediaKit
import Foundation
import os

/// Movies, series, "continue watching" and archive playback for Xtream accounts.
///
/// Catalogs are loaded on demand (they can be large) and kept in memory only. Stream URLs contain the
/// account password, so nothing here persists URLs: continue-watching entries store Xtream ids and the
/// URL is rebuilt from the Keychain-held password when played.
@MainActor
final class CatalogModel: ObservableObject {
    static let shared = CatalogModel()

    enum LoadState {
        case idle
        case loading
        case loaded(VODCatalog)
        case failed(UserFacingError)
    }

    struct Key: Hashable {
        var sourceID: String
        var kind: CatalogKind
    }

    @Published private(set) var states: [Key: LoadState] = [:]
    @Published private(set) var continueWatching: ContinueWatching

    private var targets: [String: WatchTarget] = [:]
    private var serverTimeZones: [String: TimeZone] = [:]
    private let file: SnapshotFile<ContinueWatching>
    private var lastSave = Date.distantPast
    private var isDirty = false
    private let log = Logger(subsystem: "com.bnycftc.carmedya", category: "catalog")

    /// Minimum interval between progress writes while playing.
    private let saveInterval: TimeInterval = 15

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CarMedya", isDirectory: true)
        file = SnapshotFile<ContinueWatching>(url: support.appendingPathComponent("continue-watching.json"))
        continueWatching = (try? file.load()) ?? ContinueWatching()
        for entry in continueWatching.entries {
            targets[entry.id] = entry.target
        }
    }

    // MARK: Sources

    /// Xtream accounts (the only sources with movie and series catalogs).
    var xtreamRecords: [SourceRecord] {
        AppModel.shared.records.filter { $0.source.isXtream }
    }

    // MARK: Catalogs

    func state(sourceID: String, kind: CatalogKind) -> LoadState {
        states[Key(sourceID: sourceID, kind: kind)] ?? .idle
    }

    /// Loads a catalog unless it is already loaded (or loading).
    func load(sourceID: String, kind: CatalogKind, force: Bool = false) async {
        let key = Key(sourceID: sourceID, kind: kind)
        switch states[key] {
        case .loading?:
            return
        case .loaded?:
            if !force { return }
        default:
            break
        }
        states[key] = .loading
        do {
            let client = try AppModel.shared.xtreamClient(sourceID: sourceID)
            let catalog: VODCatalog
            switch kind {
            case .movie:
                async let categories = client.vodCategories()
                let streams = try await client.vodStreams()
                let names = (try? await categories) ?? []
                catalog = await Task.detached(priority: .userInitiated) {
                    VODCatalog.movies(sourceID: sourceID, streams: streams, categories: names)
                }.value
            case .series:
                async let categories = client.seriesCategories()
                let list = try await client.series()
                let names = (try? await categories) ?? []
                catalog = await Task.detached(priority: .userInitiated) {
                    VODCatalog.series(sourceID: sourceID, list: list, categories: names)
                }.value
            }
            states[key] = .loaded(catalog)
        } catch {
            let failure = UserFacingError.from(error)
            log.error("Catalog load failed: \(String(describing: failure), privacy: .public)")
            states[key] = .failed(failure)
        }
    }

    func vodInfo(for item: CatalogItem) async throws -> XtreamVODInfo {
        try await AppModel.shared.xtreamClient(sourceID: item.sourceID).vodInfo(vodID: item.xtreamID)
    }

    func seriesInfo(for item: CatalogItem) async throws -> XtreamSeriesInfo {
        try await AppModel.shared.xtreamClient(sourceID: item.sourceID).seriesInfo(seriesID: item.xtreamID)
    }

    /// Forgets catalogs and progress of a removed source.
    func forget(sourceID: String) {
        states = states.filter { $0.key.sourceID != sourceID }
        continueWatching.removeAll(sourceID: sourceID)
        targets = targets.filter { $0.value.sourceID != sourceID }
        save(force: true)
    }

    // MARK: Playables

    func movieTarget(_ item: CatalogItem) -> WatchTarget {
        WatchTarget(
            sourceID: item.sourceID, kind: .movie, xtreamID: item.xtreamID,
            containerExtension: item.containerExtension, title: item.title, poster: item.poster
        )
    }

    func episodeTarget(_ episode: XtreamEpisode, series: CatalogItem) -> WatchTarget {
        WatchTarget(
            sourceID: series.sourceID, kind: .series, xtreamID: series.xtreamID,
            episodeID: episode.episodeID, containerExtension: episode.containerExtension,
            title: series.title, subtitle: Self.episodeLine(episode), poster: episode.info?.movieImage ?? series.poster
        )
    }

    /// Builds the playable for a target (URL from the Keychain-held password).
    func channel(for target: WatchTarget) throws -> Channel {
        let client = try AppModel.shared.xtreamClient(sourceID: target.sourceID)
        let url: URL
        let title: String
        let group: String?
        switch target.kind {
        case .movie:
            url = client.endpoints.movieURL(streamID: target.xtreamID, containerExtension: target.containerExtension)
            title = target.title
            group = nil
        case .series:
            url = client.endpoints.seriesEpisodeURL(
                episodeID: target.episodeID ?? "", containerExtension: target.containerExtension
            )
            title = target.subtitle ?? target.title
            group = target.title
        }
        let id = target.playableID
        targets[id] = target
        AppModel.shared.registerPlayable(id, sourceID: target.sourceID)
        return Channel(
            id: id,
            title: title,
            streamURL: url,
            kind: target.kind == .movie ? .movie : .series,
            groupTitle: group,
            logo: target.poster
        )
    }

    /// Whether AVPlayer can play the target at all (MKV, AVI… cannot).
    func unsupportedReason(for target: WatchTarget) -> UnsupportedReason? {
        guard let channel = try? channel(for: target) else { return nil }
        if case .unsupported(let reason) = PlaybackURLResolver().resolve(channel, isXtreamSource: true) {
            return reason
        }
        return nil
    }

    /// Plays a movie or episode, optionally from the saved position.
    func play(_ target: WatchTarget, resume: Bool, queue: [WatchTarget] = []) {
        do {
            let channel = try channel(for: target)
            let queueChannels = queue.compactMap { try? self.channel(for: $0) }
            let start = resume ? continueWatching.resumePosition(for: target.playableID) : nil
            PlaybackController.shared.play(channel, queue: queueChannels, startAt: start)
        } catch {
            log.error("Cannot build playable: \(String(describing: UserFacingError.from(error)), privacy: .public)")
        }
    }

    // MARK: Progress

    /// Called by the player about once a second for on-demand items.
    func recordProgress(channelID: String, position: Double, duration: Double?) {
        guard let target = targets[channelID], let duration else { return }
        if continueWatching.record(target, position: position, duration: duration) {
            isDirty = true
            save(force: false)
        }
    }

    /// Writes pending progress (pause, stop, background).
    func flush() {
        save(force: true)
    }

    func removeProgress(id: String) {
        if continueWatching.remove(id: id) {
            isDirty = true
            save(force: true)
        }
    }

    func clearHistory() {
        continueWatching.clear()
        isDirty = true
        save(force: true)
    }

    private func save(force: Bool) {
        guard isDirty else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSave) >= saveInterval else { return }
        lastSave = now
        isDirty = false
        do {
            try file.save(continueWatching)
        } catch {
            log.error("Saving continue-watching failed")
        }
    }

    // MARK: Archive (catch-up)

    /// The playable for a past programme of `channel`, or `nil` if the channel has no usable archive.
    func catchupChannel(for channel: Channel, programme: Programme) async -> Channel? {
        guard let record = AppModel.shared.record(forChannelID: channel.id) else { return nil }
        var timeZone = TimeZone(identifier: "UTC")!
        if CatchupURLBuilder.mode(of: channel) == "xc" {
            timeZone = await serverTimeZone(sourceID: record.id)
        }
        guard let url = CatchupURLBuilder.url(
            for: channel, start: programme.start, end: programme.stop, now: Date(), timeZone: timeZone
        ) else { return nil }
        let id = StableID.make("catchup", channel.id, String(Int(programme.start.timeIntervalSince1970)))
        AppModel.shared.registerPlayable(id, sourceID: record.id)
        return Channel(
            id: id,
            title: programme.title.isEmpty ? channel.title : programme.title,
            streamURL: url,
            kind: .movie,
            groupTitle: channel.title,
            logo: channel.logo,
            duration: programme.duration,
            userAgent: channel.userAgent,
            referrer: channel.referrer
        )
    }

    /// Xtream servers expect timeshift start times in their own time zone (`server_info.timezone`).
    private func serverTimeZone(sourceID: String) async -> TimeZone {
        if let cached = serverTimeZones[sourceID] { return cached }
        let fallback = TimeZone(identifier: "UTC")!
        guard let client = try? AppModel.shared.xtreamClient(sourceID: sourceID),
              let info = try? await client.accountInfo(),
              let name = info.serverInfo?.timezone,
              let zone = TimeZone(identifier: name) else { return fallback }
        serverTimeZones[sourceID] = zone
        return zone
    }

    // MARK: Formatting

    /// "S1 · B3 — Başlık".
    static func episodeLine(_ episode: XtreamEpisode) -> String {
        var parts: [String] = []
        if let season = episode.season { parts.append("S\(season)") }
        if let number = episode.episodeNum { parts.append("B\(number)") }
        let code = parts.joined(separator: " · ")
        let title = episode.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (code.isEmpty, title.isEmpty) {
        case (false, false): return code + " \u{2014} " + title
        case (false, true): return code
        case (true, false): return title
        case (true, true): return "#" + (episode.episodeID ?? "")
        }
    }
}
