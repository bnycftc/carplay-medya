import Foundation
import CarMediaCore

/// What to rebuild when the user resumes an item. Contains Xtream ids only, never URLs.
public struct WatchTarget: Sendable, Hashable, Codable {
    /// Source (account) id.
    public var sourceID: String
    /// Movie or series.
    public var kind: CatalogKind
    /// Movie `stream_id`, or the `series_id` for episodes.
    public var xtreamID: Int
    /// Episode id for series episodes.
    public var episodeID: String?
    /// File container (`mp4`, `m3u8`…).
    public var containerExtension: String?
    /// Movie or series title.
    public var title: String
    /// Episode line, e.g. "S1 · B3 — Başlangıç".
    public var subtitle: String?
    /// Poster address.
    public var poster: String?

    /// Creates a target.
    public init(
        sourceID: String,
        kind: CatalogKind,
        xtreamID: Int,
        episodeID: String? = nil,
        containerExtension: String? = nil,
        title: String,
        subtitle: String? = nil,
        poster: String? = nil
    ) {
        self.sourceID = sourceID
        self.kind = kind
        self.xtreamID = xtreamID
        self.episodeID = episodeID
        self.containerExtension = containerExtension
        self.title = title
        self.subtitle = subtitle
        self.poster = poster
    }

    /// Id of the playable (same value the app uses as the ``Channel`` id).
    public var playableID: String {
        switch kind {
        case .movie:
            return StableID.make("vod", sourceID, "movie", String(xtreamID))
        case .series:
            return StableID.make("vod", sourceID, "episode", String(xtreamID), episodeID ?? "")
        }
    }

    /// Poster as a URL.
    public var posterURL: URL? { poster.flatMap { PercentEncoding.lenientURL($0) } }
}

/// Saved position of one movie or episode.
public struct WatchProgress: Sendable, Hashable, Codable, Identifiable {
    /// Playable id (``WatchTarget/playableID``).
    public var id: String
    /// What to play.
    public var target: WatchTarget
    /// Position in seconds.
    public var position: Double
    /// Duration in seconds.
    public var duration: Double
    /// Last update.
    public var updatedAt: Date

    /// Watched fraction 0…1.
    public var fraction: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }

    /// Minutes left, rounded up.
    public var minutesRemaining: Int { max(0, Int(((duration - position) / 60).rounded(.up))) }
}

/// "Continue watching" list and watched marks for movies and episodes.
///
/// Rules:
/// - positions under ``minimumPosition`` are ignored (so starting over or an early tick never erases progress),
/// - reaching ``finishedFraction`` marks the item watched and drops it from the list,
/// - the list keeps the ``capacity`` most recent items; watched marks keep the last ``watchedCapacity``.
public struct ContinueWatching: Sendable, Hashable, Codable {
    /// Positions below this many seconds are not saved.
    public static let minimumPosition: Double = 60
    /// Fraction at which an item counts as watched.
    public static let finishedFraction: Double = 0.95
    /// Seconds rewound when resuming, so the viewer regains context.
    public static let resumeRewind: Double = 5
    /// Maximum number of in-progress items.
    public static let capacity = 30
    /// Maximum number of watched marks.
    public static let watchedCapacity = 1000

    /// In-progress items, most recent first.
    public private(set) var entries: [WatchProgress]
    /// Ids of finished items, most recent last.
    public private(set) var watchedIDs: [String]

    /// Creates an empty list.
    public init() {
        entries = []
        watchedIDs = []
    }

    /// Records a position. Returns `true` if the stored state changed.
    @discardableResult
    public mutating func record(_ target: WatchTarget, position: Double, duration: Double, at date: Date = Date()) -> Bool {
        guard position.isFinite, duration.isFinite, duration > 0, position >= 0 else { return false }
        let id = target.playableID
        if position / duration >= Self.finishedFraction {
            let removed = remove(id: id)
            let wasWatched = watchedIDs.contains(id)
            if !wasWatched {
                watchedIDs.append(id)
                if watchedIDs.count > Self.watchedCapacity {
                    watchedIDs.removeFirst(watchedIDs.count - Self.watchedCapacity)
                }
            }
            return removed || !wasWatched
        }
        guard position >= Self.minimumPosition else { return false }
        let progress = WatchProgress(id: id, target: target, position: position, duration: duration, updatedAt: date)
        if let existing = entries.firstIndex(where: { $0.id == id }) {
            entries.remove(at: existing)
        }
        entries.insert(progress, at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
        watchedIDs.removeAll { $0 == id }
        return true
    }

    /// Where to resume `id`, or `nil` when there is no saved position.
    public func resumePosition(for id: String) -> Double? {
        guard let entry = progress(for: id) else { return nil }
        return max(0, entry.position - Self.resumeRewind)
    }

    /// Saved progress of `id`.
    public func progress(for id: String) -> WatchProgress? {
        entries.first { $0.id == id }
    }

    /// Whether `id` was watched to the end.
    public func isWatched(_ id: String) -> Bool {
        watchedIDs.contains(id)
    }

    /// Removes `id` from the in-progress list. Returns `true` if it was there.
    @discardableResult
    public mutating func remove(id: String) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries.remove(at: index)
        return true
    }

    /// Drops everything that belongs to a removed source.
    public mutating func removeAll(sourceID: String) {
        entries.removeAll { $0.target.sourceID == sourceID }
    }

    /// Clears progress and watched marks.
    public mutating func clear() {
        entries = []
        watchedIDs = []
    }
}
