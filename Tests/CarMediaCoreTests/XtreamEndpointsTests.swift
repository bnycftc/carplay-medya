import Foundation
import XCTest
@testable import CarMediaCore

final class XtreamEndpointsTests: XCTestCase {
    private func endpoints(password: String = "p4ss") throws -> XtreamEndpoints {
        XtreamEndpoints(credentials: try XtreamCredentials(baseURL: "http://iptv.example.com:8080", username: "demo", password: password))
    }

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    func testBaseURLNormalization() {
        let cases: [(String, String)] = [
            ("iptv.example.com:8080", "http://iptv.example.com:8080"),
            ("http://iptv.example.com:8080/", "http://iptv.example.com:8080"),
            ("  HTTPS://IPTV.Example.com  ", "https://iptv.example.com"),
            ("http://iptv.example.com:8080/get.php?username=u&password=p&type=m3u_plus", "http://iptv.example.com:8080"),
            ("http://iptv.example.com/panel/player_api.php", "http://iptv.example.com/panel"),
            ("http://iptv.example.com///", "http://iptv.example.com"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(XtreamCredentials.normalizeBaseURL(input)?.absoluteString, expected, "input: \(input)")
        }
        XCTAssertNil(XtreamCredentials.normalizeBaseURL(""))
        XCTAssertNil(XtreamCredentials.normalizeBaseURL("ftp://iptv.example.com"))
    }

    func testInvalidCredentialsThrow() {
        assertThrows(.invalidURL("server address")) { try XtreamCredentials(baseURL: "   ", username: "u", password: "p") }
        assertThrows(.invalidURL("username")) { try XtreamCredentials(baseURL: "iptv.example.com", username: " ", password: "p") }
        assertThrows(.invalidURL("password")) { try XtreamCredentials(baseURL: "iptv.example.com", username: "u", password: "") }
    }

    func testDescriptionAndDumpNeverRevealPassword() throws {
        let credentials = try XtreamCredentials(baseURL: "iptv.example.com", username: "demo", password: "TopSecret123")
        XCTAssertFalse(credentials.description.contains("TopSecret123"))
        XCTAssertFalse(String(describing: credentials).contains("TopSecret123"))
        XCTAssertFalse(String(reflecting: credentials).contains("TopSecret123"))
        var dumped = ""
        dump(credentials, to: &dumped)
        XCTAssertFalse(dumped.contains("TopSecret123"))
        XCTAssertTrue(credentials.description.contains(Redaction.placeholder))
    }

    func testAccountInfoURLHasNoAction() throws {
        let url = try endpoints().accountInfo
        XCTAssertEqual(url.absoluteString, "http://iptv.example.com:8080/player_api.php?username=demo&password=p4ss")
    }

    func testPlayerAPIActionsAndParams() throws {
        let e = try endpoints()
        XCTAssertEqual(query(e.liveCategories)["action"], "get_live_categories")
        XCTAssertEqual(query(e.vodCategories)["action"], "get_vod_categories")
        XCTAssertEqual(query(e.seriesCategories)["action"], "get_series_categories")
        XCTAssertEqual(query(e.liveStreams(categoryID: "5")), ["username": "demo", "password": "p4ss", "action": "get_live_streams", "category_id": "5"])
        XCTAssertNil(query(e.liveStreams())["category_id"])
        XCTAssertEqual(query(e.vodStreams(categoryID: "7"))["category_id"], "7")
        XCTAssertEqual(query(e.series(categoryID: "9"))["action"], "get_series")
        XCTAssertEqual(query(e.seriesInfo(seriesID: 301))["series_id"], "301")
        XCTAssertEqual(query(e.vodInfo(vodID: 2001))["vod_id"], "2001")
        XCTAssertEqual(query(e.shortEPG(streamID: 101, limit: 4)), ["username": "demo", "password": "p4ss", "action": "get_short_epg", "stream_id": "101", "limit": "4"])
        XCTAssertNil(query(e.shortEPG(streamID: 101))["limit"])
        XCTAssertEqual(query(e.simpleDataTable(streamID: 101))["action"], "get_simple_data_table")
        // Deterministic ordering: params sorted by key after the fixed prefix.
        XCTAssertTrue(e.shortEPG(streamID: 1, limit: 2).absoluteString.hasSuffix("action=get_short_epg&limit=2&stream_id=1"))
    }

    func testSpecialCharactersInPasswordAreEncoded() throws {
        let e = try endpoints(password: "a+b&c=d/é")
        let url = e.accountInfo.absoluteString
        XCTAssertTrue(url.hasSuffix("password=a%2Bb%26c%3Dd%2F%C3%A9"), url)
        XCTAssertEqual(query(e.accountInfo)["password"], "a+b&c=d/é")
        XCTAssertTrue(e.liveStreamURL(streamID: 1).absoluteString.hasSuffix("/live/demo/a%2Bb%26c%3Dd%2F%C3%A9/1.m3u8"))
    }

    func testStreamURLBuilders() throws {
        let e = try endpoints()
        XCTAssertEqual(e.liveStreamURL(streamID: 101).absoluteString, "http://iptv.example.com:8080/live/demo/p4ss/101.m3u8")
        XCTAssertEqual(e.liveStreamURL(streamID: 101, format: .mpegTS).absoluteString, "http://iptv.example.com:8080/live/demo/p4ss/101.ts")
        XCTAssertEqual(e.movieURL(streamID: 2001, containerExtension: "MKV").absoluteString, "http://iptv.example.com:8080/movie/demo/p4ss/2001.mkv")
        XCTAssertEqual(e.movieURL(streamID: 2002, containerExtension: nil).absoluteString, "http://iptv.example.com:8080/movie/demo/p4ss/2002.mp4")
        XCTAssertEqual(e.seriesEpisodeURL(episodeID: "5001", containerExtension: ".mp4").absoluteString, "http://iptv.example.com:8080/series/demo/p4ss/5001.mp4")
    }

    func testXMLTVAndM3UExportURLs() throws {
        let e = try endpoints()
        XCTAssertEqual(e.xmltvURL.absoluteString, "http://iptv.example.com:8080/xmltv.php?username=demo&password=p4ss")
        XCTAssertEqual(e.m3uURL().absoluteString, "http://iptv.example.com:8080/get.php?username=demo&password=p4ss&type=m3u_plus&output=m3u8")
        XCTAssertEqual(query(e.m3uURL(output: .mpegTS))["output"], "ts")
    }

    func testRedactionRemovesRawAndEncodedSecrets() {
        let text = "failed http://x.example.com/live/u/a%2Bb/1.m3u8 and a+b"
        let redacted = Redaction.redact(text, secrets: ["a+b"])
        XCTAssertFalse(redacted.contains("a+b"))
        XCTAssertFalse(redacted.contains("a%2Bb"))
    }
}
