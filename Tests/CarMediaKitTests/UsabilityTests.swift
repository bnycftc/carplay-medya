import Foundation
import XCTest
import CarMediaCore
@testable import CarMediaKit

final class SourceLinkParserTests: XCTestCase {
    func testGetPhpLinkBecomesXtreamAccount() {
        XCTAssertEqual(
            SourceLinkParser.detect("http://tv.example.com:8080/get.php?username=ali&password=Gizli123&type=m3u_plus&output=ts"),
            .xtream(server: "http://tv.example.com:8080", username: "ali", password: "Gizli123")
        )
        XCTAssertEqual(
            SourceLinkParser.detect("  https://tv.example.com/panel/player_api.php?password=p%40ss&username=veli \n"),
            .xtream(server: "https://tv.example.com/panel", username: "veli", password: "p@ss")
        )
    }

    func testStreamURLRevealsAccount() {
        XCTAssertEqual(
            SourceLinkParser.detect("http://tv.example.com:80/live/ali/p%40ss/1234.ts"),
            .xtream(server: "http://tv.example.com:80", username: "ali", password: "p@ss")
        )
    }

    func testPlainPlaylistStaysM3U() {
        XCTAssertEqual(SourceLinkParser.detect("https://lists.example.com/benim/liste.m3u"),
                       .m3u(url: "https://lists.example.com/benim/liste.m3u"))
        XCTAssertEqual(SourceLinkParser.detect("Listem: https://lists.example.com/a.m3u8, iyi seyirler."),
                       .m3u(url: "https://lists.example.com/a.m3u8"))
        XCTAssertNil(SourceLinkParser.detect("merhaba"))
    }

    func testIncompleteGetPhpFallsBackToM3U() {
        XCTAssertEqual(SourceLinkParser.detect("http://tv.example.com/get.php?username=ali"),
                       .m3u(url: "http://tv.example.com/get.php?username=ali"))
    }

    func testProviderMessageInTurkish() {
        let message = """
        ✅ Hesabınız hazır!
        🌐 Sunucu: http://tv.example.com:8080
        👤 Kullanıcı Adı: ali123
        🔑 Şifre: X9y8Z7
        Bitiş: 01.01.2027
        """
        XCTAssertEqual(SourceLinkParser.detect(message),
                       .xtream(server: "http://tv.example.com:8080", username: "ali123", password: "X9y8Z7"))
    }

    func testProviderMessageWithSeparatePortAndNoScheme() {
        let message = "Host = tv.example.com\nPort = 25461\nUsername = demo\nPassword = demo123"
        XCTAssertEqual(SourceLinkParser.detect(message),
                       .xtream(server: "http://tv.example.com:25461", username: "demo", password: "demo123"))
    }

    func testM3UAddressConversionCheck() {
        let url = URL(string: "http://tv.example.com:8080/get.php?username=a&password=b&type=m3u_plus")!
        XCTAssertEqual(SourceLinkParser.xtreamAccount(inM3UAddress: url),
                       .xtream(server: "http://tv.example.com:8080", username: "a", password: "b"))
        XCTAssertNil(SourceLinkParser.xtreamAccount(inM3UAddress: URL(string: "http://lists.example.com/a.m3u")!))
    }

    func testKeyNormalization() {
        XCTAssertEqual(SourceLinkParser.normalizeKey("🔑 KULLANICI ADI"), "kullaniciadi")
        XCTAssertEqual(SourceLinkParser.normalizeKey("Şifre"), "sifre")
    }
}

final class ReconnectPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testBacksOffThenGivesUp() {
        var policy = ReconnectPolicy()
        XCTAssertEqual(policy.noteFailure(at: t0), 2)
        XCTAssertEqual(policy.noteFailure(at: t0.addingTimeInterval(3)), 5)
        XCTAssertEqual(policy.noteFailure(at: t0.addingTimeInterval(9)), 10)
        XCTAssertNil(policy.noteFailure(at: t0.addingTimeInterval(20)))
        XCTAssertEqual(policy.attempt, ReconnectPolicy.maxAttempts)
    }

    func testStablePlaybackResetsAttempts() {
        var policy = ReconnectPolicy()
        _ = policy.noteFailure(at: t0)
        _ = policy.noteFailure(at: t0)
        policy.markPlaying(at: t0.addingTimeInterval(10))
        XCTAssertEqual(policy.noteFailure(at: t0.addingTimeInterval(20)), 10, "10 s of playback is not stable yet")
        policy.markPlaying(at: t0.addingTimeInterval(30))
        XCTAssertEqual(policy.noteFailure(at: t0.addingTimeInterval(30 + ReconnectPolicy.stableInterval)), 2)
    }

    func testResetStartsOver() {
        var policy = ReconnectPolicy()
        for _ in 0..<5 { _ = policy.noteFailure(at: t0) }
        policy.reset()
        XCTAssertEqual(policy.noteFailure(at: t0), 2)
    }
}

final class HiddenGroupTests: XCTestCase {
    private func library() -> LibraryState {
        func channel(_ id: String, _ group: String) -> Channel {
            Channel(id: id, title: id, streamURL: URL(string: "http://tv.example.com/\(id).m3u8")!, groupTitle: group)
        }
        let playlist = Playlist(channels: [channel("a", "Haber"), channel("b", "Spor"), channel("c", "Yabancı")])
        var state = LibraryState()
        state.setContent([(id: "s1", name: "Liste", playlist: playlist)])
        return state
    }

    func testHidingGroupsFiltersVisibleSections() throws {
        var state = library()
        XCTAssertEqual(state.visibleGroups.count, 3)
        let foreign = try XCTUnwrap(state.groups.first { $0.name == "Yabancı" })
        state.setGroup(foreign.id, hidden: true)
        XCTAssertTrue(state.isGroupHidden(foreign.id))
        XCTAssertEqual(state.visibleGroups.map(\.name), ["Haber", "Spor"])
        XCTAssertEqual(state.groups.count, 3, "hidden groups stay available for editing")
        XCTAssertEqual(state.search("c").map(\.id), ["c"], "search still finds hidden channels")
        state.setGroup(foreign.id, hidden: false)
        XCTAssertEqual(state.visibleGroups.count, 3)
    }

    func testHideAllOfSourceDropsSection() {
        var state = library()
        state.setAllGroups(ofSource: "s1", hidden: true)
        XCTAssertTrue(state.visibleSections.isEmpty)
        state.setAllGroups(ofSource: "s1", hidden: false)
        XCTAssertEqual(state.visibleSections.first?.groups.count, 3)
        XCTAssertTrue(state.preferences.hiddenGroupIDs.isEmpty)
    }

    func testOldPreferenceFilesStillDecode() throws {
        let old = Data(#"{"favoriteIDs":["a"],"recentIDs":["b"]}"#.utf8)
        let decoded = try JSONDecoder().decode(LibraryPreferences.self, from: old)
        XCTAssertEqual(decoded.favoriteIDs, ["a"])
        XCTAssertEqual(decoded.hiddenGroupIDs, [])
        let roundTrip = try JSONDecoder().decode(LibraryPreferences.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(roundTrip, decoded)
    }
}
