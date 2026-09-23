import Foundation
import XCTest
import CarMediaCore
@testable import CarMediaKit

final class SourceStoreTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore(_ provider: StubPlaylistProvider, snapshot: SourceStoreSnapshot = .empty) -> InMemorySourceStore {
        let date = fixedDate
        return InMemorySourceStore(snapshot: snapshot, provider: provider, now: { date })
    }

    func testAddRemoveAndDuplicateDetection() async throws {
        let store = makeStore(StubPlaylistProvider())
        try await store.add(Sample.m3uSource())
        do {
            try await store.add(Sample.m3uSource(id: "other-id"))
            XCTFail("same list URL must be rejected")
        } catch let error as SourceStoreError {
            XCTAssertEqual(error, .duplicateSource)
        }
        try await store.add(Sample.xtreamSource())
        let ids = await store.records().map(\.id)
        XCTAssertEqual(ids, ["m3u-1", "xt-1"])

        await store.remove(sourceID: "m3u-1")
        let remaining = await store.records().map(\.id)
        XCTAssertEqual(remaining, ["xt-1"])
    }

    func testRefreshStoresPlaylistAndBookkeeping() async throws {
        let playlist = Playlist(channels: [Sample.channel("Bir"), Sample.channel("İki")])
        let store = makeStore(StubPlaylistProvider(["m3u-1": .success(playlist)]))
        try await store.add(Sample.m3uSource())

        let loaded = try await store.refresh(sourceID: "m3u-1")
        XCTAssertEqual(loaded.channels.count, 2)
        let first = await store.records().first
        let record = try XCTUnwrap(first)
        XCTAssertEqual(record.channelCount, 2)
        XCTAssertEqual(record.lastRefreshedAt, fixedDate)
        XCTAssertNil(record.lastError)
        let cached = await store.playlist(forSourceID: "m3u-1")
        XCTAssertEqual(cached, playlist)
    }

    func testRefreshFailureIsClassifiedWithoutText() async throws {
        let provider = StubPlaylistProvider(["m3u-1": .failure(CarMediaError.httpStatus(404))])
        let store = makeStore(provider)
        try await store.add(Sample.m3uSource())
        do {
            try await store.refresh(sourceID: "m3u-1")
            XCTFail("expected failure")
        } catch {}
        let first = await store.records().first
        let record = try XCTUnwrap(first)
        XCTAssertEqual(record.lastError, .httpStatus(404))

        provider.set(.success(Playlist(channels: [Sample.channel("Bir")])), for: "m3u-1")
        try await store.refresh(sourceID: "m3u-1")
        let refreshedFirst = await store.records().first
        let refreshed = try XCTUnwrap(refreshedFirst)
        XCTAssertNil(refreshed.lastError, "success clears the previous error")
    }

    func testRefreshUnknownSourceThrows() async {
        let store = makeStore(StubPlaylistProvider())
        do {
            try await store.refresh(sourceID: "missing")
            XCTFail("expected failure")
        } catch let error as SourceStoreError {
            XCTAssertEqual(error, .unknownSource)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testSnapshotRoundTripKeepsM3UButNeverXtreamPlaylists() async throws {
        let password = "gizli-Parola+1"
        let creds = try XtreamCredentials(baseURL: "panel.example.com:8080", username: "demo", password: password)
        let xtreamChannel = Channel(
            id: "x1", title: "Xtream Kanal",
            streamURL: XtreamEndpoints(credentials: creds).liveStreamURL(streamID: 7)
        )
        let provider = StubPlaylistProvider([
            "m3u-1": .success(Playlist(channels: [Sample.channel("Bir")])),
            "xt-1": .success(Playlist(channels: [xtreamChannel])),
        ])
        let store = makeStore(provider)
        try await store.add(Sample.m3uSource())
        try await store.add(Sample.xtreamSource())
        try await store.refresh(sourceID: "m3u-1")
        try await store.refresh(sourceID: "xt-1")

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.records.count, 2)
        XCTAssertEqual(Array(snapshot.playlists.keys), ["m3u-1"])

        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(json.contains(password), "snapshot must never contain the Xtream password")
        XCTAssertFalse(json.contains(PercentEncoding.encodeComponent(password)))

        let decoded = try JSONDecoder().decode(SourceStoreSnapshot.self, from: try JSONEncoder().encode(snapshot))
        let restored = makeStore(StubPlaylistProvider(), snapshot: decoded)
        let restoredIDs = await restored.records().map(\.id)
        XCTAssertEqual(restoredIDs, ["m3u-1", "xt-1"])
        let restoredPlaylist = await restored.playlist(forSourceID: "m3u-1")
        XCTAssertEqual(restoredPlaylist?.channels.first?.title, "Bir")
    }

    func testRestoreDropsPlaylistsOfUnknownOrXtreamSources() async {
        let snapshot = SourceStoreSnapshot(
            records: [SourceRecord(source: Sample.xtreamSource(), addedAt: fixedDate)],
            playlists: [
                "xt-1": Playlist(channels: [Sample.channel("A")]),
                "ghost": Playlist(channels: [Sample.channel("B")]),
            ]
        )
        let store = makeStore(StubPlaylistProvider(), snapshot: snapshot)
        let xtream = await store.playlist(forSourceID: "xt-1")
        let ghost = await store.playlist(forSourceID: "ghost")
        XCTAssertNil(xtream)
        XCTAssertNil(ghost)
    }

    func testRenameKeepsIdentity() async throws {
        let store = makeStore(StubPlaylistProvider())
        try await store.add(Sample.m3uSource())
        try await store.rename(sourceID: "m3u-1", to: "  Evdeki liste ")
        let first = await store.records().first
        let record = try XCTUnwrap(first)
        XCTAssertEqual(record.source.name, "Evdeki liste")
        XCTAssertEqual(record.id, "m3u-1")
    }

    func testSnapshotFilePersistsToDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = SnapshotFile<LibraryPreferences>(url: dir.appendingPathComponent("prefs.json"))
        XCTAssertNil(try file.load())
        let prefs = LibraryPreferences(favoriteIDs: ["a", "b"], recentIDs: ["b"])
        try file.save(prefs)
        XCTAssertEqual(try file.load(), prefs)
        try file.delete()
        XCTAssertNil(try file.load())
    }
}
