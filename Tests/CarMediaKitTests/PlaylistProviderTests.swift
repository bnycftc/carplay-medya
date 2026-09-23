import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CarMediaCore
@testable import CarMediaKit

final class PlaylistProviderTests: XCTestCase {
    private func provider(
        _ transport: KitStubTransport,
        credentials: CredentialStore = InMemoryCredentialStore(),
        bookmark: @escaping DefaultPlaylistProvider.BookmarkResolver = { _ in throw SourceStoreError.fileUnavailable }
    ) -> DefaultPlaylistProvider {
        DefaultPlaylistProvider(transport: transport, credentials: credentials, resolveBookmark: bookmark)
    }

    func testM3USourceIsDownloadedAndParsed() async throws {
        let transport = KitStubTransport { _ in (200, Sample.m3uText) }
        let playlist = try await provider(transport).loadPlaylist(for: Sample.m3uSource())
        XCTAssertEqual(playlist.channels.map(\.title), ["Haber Bir", "Radyo Deneme"])
        XCTAssertEqual(transport.requestedURLs, [Sample.listURL])
    }

    func testXtreamWithoutStoredPasswordFails() async {
        let transport = KitStubTransport { _ in (200, "[]") }
        do {
            _ = try await provider(transport).loadPlaylist(for: Sample.xtreamSource())
            XCTFail("expected missing password")
        } catch {
            XCTAssertEqual(UserFacingError.from(error), .missingPassword)
        }
        XCTAssertTrue(transport.requestedURLs.isEmpty, "no request without a password")
    }

    func testXtreamBuildsHLSChannelsWithCategoryNames() async throws {
        let transport = KitStubTransport { request in
            let action = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "action" }?.value
            switch action {
            case "get_live_categories"?:
                return (200, #"[{"category_id":"5","category_name":"Belgesel"}]"#)
            case "get_live_streams"?:
                return (200, #"[{"stream_id":42,"name":"Doğa","category_id":"5","stream_type":"live"}]"#)
            default:
                return (404, "")
            }
        }
        let credentials = InMemoryCredentialStore(passwords: ["xt-1": "p4ss"])
        let playlist = try await provider(transport, credentials: credentials).loadPlaylist(for: Sample.xtreamSource())
        let channel = try XCTUnwrap(playlist.channels.first)
        XCTAssertEqual(channel.title, "Doğa")
        XCTAssertEqual(channel.groupTitle, "Belgesel")
        XCTAssertEqual(channel.streamURL.pathExtension, "m3u8")
    }

    func testLocalMediaFileBecomesSingleItemPlaylist() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("tatil.mp4")
        try Data([0, 0, 0, 0x18]).write(to: file)

        let source = MediaSource.localFile(id: "f1", name: "Tatil", bookmark: Data())
        let playlist = try await provider(KitStubTransport { _ in (500, "") }, bookmark: { _ in file })
            .loadPlaylist(for: source)
        XCTAssertEqual(playlist.channels.count, 1)
        XCTAssertEqual(playlist.channels.first?.title, "Tatil")
        XCTAssertEqual(playlist.channels.first?.kind, .movie)
        XCTAssertEqual(playlist.channels.first?.id, StableID.make("local", "f1"), "id must not depend on the file path")
    }

    func testLocalPlaylistFileIsParsed() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("liste.m3u")
        try Data(Sample.m3uText.utf8).write(to: file)
        let playlist = try DefaultPlaylistProvider.loadLocalFile(file, sourceID: "f2", name: "Liste")
        XCTAssertEqual(playlist.channels.count, 2)
    }

    func testUnresolvableBookmarkIsFileUnavailable() async {
        let source = MediaSource.localFile(id: "f3", name: "Kayıp", bookmark: Data([1, 2, 3]))
        do {
            _ = try await provider(KitStubTransport { _ in (500, "") }).loadPlaylist(for: source)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(UserFacingError.from(error), .fileUnavailable)
        }
    }

    func testGuideIsLoadedFromHeaderURL() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <channel id="haber.example"><display-name>Haber Bir</display-name></channel>
          <programme start="20300101200000 +0000" stop="20300101210000 +0000" channel="haber.example"><title>Akşam</title></programme>
        </tv>
        """
        let transport = KitStubTransport { request in
            request.url?.host == "guide.example.com" ? (200, xml) : (200, Sample.m3uText)
        }
        let provider = provider(transport)
        let playlist = try await provider.loadPlaylist(for: Sample.m3uSource())
        let guide = try await provider.loadGuide(for: Sample.m3uSource(), playlist: playlist)
        let store = try XCTUnwrap(guide)
        XCTAssertEqual(store.programmeCount, 1)
    }
}
