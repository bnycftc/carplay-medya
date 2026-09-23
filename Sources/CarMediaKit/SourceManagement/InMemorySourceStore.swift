import Foundation
import CarMediaCore

/// Actor-backed ``SourceStore`` that keeps everything in memory and persists via ``SourceStoreSnapshot``.
public actor InMemorySourceStore: SourceStore {
    private var orderedRecords: [SourceRecord]
    private var playlists: [String: Playlist]
    private let provider: any PlaylistProvider
    private let now: @Sendable () -> Date

    /// Creates a store, optionally restoring a snapshot.
    ///
    /// - Parameters:
    ///   - snapshot: previously saved state. Cached playlists of unknown or non-persistable sources are dropped.
    ///   - provider: loads playlists for ``refresh(sourceID:)``.
    ///   - now: clock, injectable for tests.
    public init(
        snapshot: SourceStoreSnapshot = .empty,
        provider: any PlaylistProvider,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let persistable = Set(snapshot.records.filter { $0.source.isPlaylistPersistable }.map(\.id))
        self.orderedRecords = snapshot.records
        self.playlists = snapshot.playlists.filter { persistable.contains($0.key) }
        self.provider = provider
        self.now = now
    }

    public func records() -> [SourceRecord] {
        orderedRecords
    }

    public func playlist(forSourceID id: String) -> Playlist? {
        playlists[id]
    }

    @discardableResult
    public func add(_ source: MediaSource) throws -> SourceRecord {
        if orderedRecords.contains(where: { $0.id == source.id }) { throw SourceStoreError.duplicateSource }
        if let key = source.duplicateKey, orderedRecords.contains(where: { $0.source.duplicateKey == key }) {
            throw SourceStoreError.duplicateSource
        }
        let record = SourceRecord(source: source, addedAt: now())
        orderedRecords.append(record)
        return record
    }

    public func remove(sourceID id: String) {
        orderedRecords.removeAll { $0.id == id }
        playlists[id] = nil
    }

    public func rename(sourceID id: String, to name: String) throws {
        guard let index = orderedRecords.firstIndex(where: { $0.id == id }) else {
            throw SourceStoreError.unknownSource
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        orderedRecords[index].source = orderedRecords[index].source.renamed(trimmed)
    }

    @discardableResult
    public func refresh(sourceID id: String) async throws -> Playlist {
        guard let record = orderedRecords.first(where: { $0.id == id }) else {
            throw SourceStoreError.unknownSource
        }
        let playlist: Playlist
        do {
            playlist = try await provider.loadPlaylist(for: record.source)
        } catch {
            if let index = orderedRecords.firstIndex(where: { $0.id == id }) {
                orderedRecords[index].lastError = UserFacingError.from(error)
            }
            throw error
        }
        // The source may have been removed while loading (actor reentrancy).
        guard let index = orderedRecords.firstIndex(where: { $0.id == id }) else {
            throw SourceStoreError.unknownSource
        }
        orderedRecords[index].lastRefreshedAt = now()
        orderedRecords[index].channelCount = playlist.channels.count
        orderedRecords[index].lastError = nil
        playlists[id] = playlist
        return playlist
    }

    public func snapshot() -> SourceStoreSnapshot {
        let persistable = Set(orderedRecords.filter { $0.source.isPlaylistPersistable }.map(\.id))
        return SourceStoreSnapshot(
            records: orderedRecords,
            playlists: playlists.filter { persistable.contains($0.key) }
        )
    }
}
