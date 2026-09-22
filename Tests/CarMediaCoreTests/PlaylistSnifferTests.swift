import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CarMediaCore

final class PlaylistSnifferTests: XCTestCase {
    func testChannelPlaylistDetected() throws {
        XCTAssertEqual(PlaylistSniffer.classify(data: try Fixture.data("sample.m3u")), .channelPlaylist)
    }

    func testHLSMediaAndMasterDetected() throws {
        XCTAssertEqual(PlaylistSniffer.classify(data: try Fixture.data("hls_media.m3u8")), .hlsMediaPlaylist)
        XCTAssertEqual(PlaylistSniffer.classify(data: try Fixture.data("hls_master.m3u8")), .hlsMediaPlaylist)
    }

    func testMPEGTSSyncPatternDetected() {
        var bytes = [UInt8](repeating: 0xAB, count: 188 * 4)
        for packet in 0..<4 { bytes[packet * 188] = 0x47 }
        XCTAssertEqual(PlaylistSniffer.classify(data: Data(bytes)), .binaryMedia)
    }

    func testMP4FtypDetected() {
        var bytes: [UInt8] = [0x00, 0x00, 0x00, 0x20]
        bytes += Array("ftypisom".utf8)
        bytes += [UInt8](repeating: 0, count: 64)
        XCTAssertEqual(PlaylistSniffer.classify(data: Data(bytes)), .binaryMedia)
    }

    func testHTMLIsUnknownAndContentTypeFallback() {
        let html = Data("<html><body>Not found</body></html>".utf8)
        XCTAssertEqual(PlaylistSniffer.classify(data: html), .unknown)
        XCTAssertEqual(PlaylistSniffer.classify(data: Data([0x00, 0x01, 0x02]), contentTypeHeader: "video/mp2t"), .binaryMedia)
        // audio/x-mpegurl is a playlist type, never binary media.
        XCTAssertEqual(PlaylistSniffer.classify(data: html, contentTypeHeader: "audio/x-mpegurl"), .unknown)
    }

    func testPlainURLListIsChannelPlaylist() {
        let data = Data("http://a.example.com/1.m3u8\nhttp://a.example.com/2.m3u8\n".utf8)
        XCTAssertEqual(PlaylistSniffer.classify(data: data), .channelPlaylist)
    }

    // MARK: PlaylistLoader

    func testLoaderRejectsMediaStreamWithFriendlyError() async throws {
        let body = try Fixture.data("hls_media.m3u8")
        let loader = PlaylistLoader(transport: StubTransport { _ in (200, body, ["Content-Type": "application/vnd.apple.mpegurl"]) })
        await assertThrowsAsync(.notAChannelList(.hlsMediaPlaylist)) {
            try await loader.load(from: URL(string: "http://lists.example.com/stream.m3u8")!)
        }
        XCTAssertEqual(CarMediaError.notAChannelList(.hlsMediaPlaylist).errorDescription,
                       "This address is a media stream, not a channel list.")
    }

    func testLoaderSendsUserAgentAndParses() async throws {
        let body = try Fixture.data("sample.m3u")
        let transport = StubTransport { _ in (200, body, ["Content-Type": "audio/x-mpegurl"]) }
        let loader = PlaylistLoader(transport: transport)
        let playlist = try await loader.load(from: URL(string: "http://lists.example.com/list.m3u")!, userAgent: "Test/1.0")
        XCTAssertEqual(playlist.channels.count, 7)
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "User-Agent"), "Test/1.0")
    }

    func testLoaderMapsHTTPErrors() async {
        let loader = PlaylistLoader(transport: StubTransport { _ in (404, Data(), [:]) })
        await assertThrowsAsync(.httpStatus(404)) {
            try await loader.load(from: URL(string: "http://lists.example.com/missing.m3u")!)
        }
    }
}
