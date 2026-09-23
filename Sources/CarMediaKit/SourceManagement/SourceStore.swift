import Foundation
import CarMediaCore

/// Errors raised while managing sources.
public enum SourceStoreError: Error, Sendable, Equatable {
    /// A source with the same id (or the same list address / Xtream account) already exists.
    case duplicateSource
    /// No source with the given id.
    case unknownSource
    /// The Xtream password could not be read from secure storage.
    case missingPassword
    /// An imported file could not be resolved or read.
    case fileUnavailable
}

/// A source the user added, plus bookkeeping about its last refresh.
public struct SourceRecord: Sendable, Hashable, Codable, Identifiable {
    /// The source definition (never contains a password).
    public var source: MediaSource
    /// When the user added it.
    public var addedAt: Date
    /// Last successful refresh.
    public var lastRefreshedAt: Date?
    /// Channel count after the last successful refresh.
    public var channelCount: Int
    /// Classification of the last refresh failure, cleared on success. Never contains text from the error.
    public var lastError: UserFacingError?

    /// Creates a record.
    public init(
        source: MediaSource,
        addedAt: Date,
        lastRefreshedAt: Date? = nil,
        channelCount: Int = 0,
        lastError: UserFacingError? = nil
    ) {
        self.source = source
        self.addedAt = addedAt
        self.lastRefreshedAt = lastRefreshedAt
        self.channelCount = channelCount
        self.lastError = lastError
    }

    /// The source id.
    public var id: String { source.id }
}

/// Everything a ``SourceStore`` needs to restore itself after a relaunch.
///
/// Xtream playlists are **not** included: their stream URLs embed the account password. They are
/// rebuilt on launch from the Keychain-held password.
public struct SourceStoreSnapshot: Sendable, Hashable, Codable {
    /// Current schema version.
    public static let currentVersion = 1

    /// Schema version of this snapshot.
    public var version: Int
    /// Sources in display order.
    public var records: [SourceRecord]
    /// Cached playlists keyed by source id (M3U and local-file sources only).
    public var playlists: [String: Playlist]

    /// Creates a snapshot.
    public init(
        version: Int = SourceStoreSnapshot.currentVersion,
        records: [SourceRecord] = [],
        playlists: [String: Playlist] = [:]
    ) {
        self.version = version
        self.records = records
        self.playlists = playlists
    }

    /// An empty snapshot.
    public static let empty = SourceStoreSnapshot()
}

/// Owns the user's sources and their most recently loaded playlists.
public protocol SourceStore: AnyObject, Sendable {
    /// All sources in display order.
    func records() async -> [SourceRecord]
    /// The last successfully loaded playlist of a source.
    func playlist(forSourceID id: String) async -> Playlist?
    /// Adds a source (does not load it; call ``refresh(sourceID:)``).
    @discardableResult
    func add(_ source: MediaSource) async throws -> SourceRecord
    /// Removes a source and its cached playlist. Unknown ids are ignored.
    func remove(sourceID id: String) async
    /// Renames a source.
    func rename(sourceID id: String, to name: String) async throws
    /// Reloads a source through its provider.
    @discardableResult
    func refresh(sourceID id: String) async throws -> Playlist
    /// A persistable snapshot.
    func snapshot() async -> SourceStoreSnapshot
}

extension MediaSource {
    /// Whether playlists from this source may be persisted (their URLs carry no password).
    public var isPlaylistPersistable: Bool {
        if case .xtream = self { return false }
        return true
    }

    /// `true` for Xtream accounts (their password lives in the Keychain).
    public var isXtream: Bool {
        if case .xtream = self { return true }
        return false
    }

    /// A copy with a different display name.
    public func renamed(_ name: String) -> MediaSource {
        switch self {
        case .m3uURL(let id, _, let url, let userAgent):
            return .m3uURL(id: id, name: name, url: url, userAgent: userAgent)
        case .xtream(let id, _, let account):
            return .xtream(id: id, name: name, account: account)
        case .localFile(let id, _, let bookmark):
            return .localFile(id: id, name: name, bookmark: bookmark)
        }
    }

    /// A key identifying "the same" source for duplicate detection (`nil` for imported files).
    var duplicateKey: String? {
        switch self {
        case .m3uURL(_, _, let url, _):
            return "m3u|" + url.absoluteString
        case .xtream(_, _, let account):
            return "xtream|" + account.baseURL.absoluteString + "|" + account.username
        case .localFile:
            return nil
        }
    }
}
