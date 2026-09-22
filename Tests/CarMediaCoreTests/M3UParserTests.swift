import Foundation
import XCTest
@testable import CarMediaCore

final class M3UParserTests: XCTestCase {
    private let parser = M3UParser()

    private func sample() throws -> Playlist {
        try parser.parse(data: Fixture.data("sample.m3u"))
    }

    private func channel(_ playlist: Playlist, titled title: String) throws -> Channel {
        try XCTUnwrap(playlist.channels.first { $0.title == title }, "missing channel \(title)")
    }

    // MARK: Fixture

    func testSampleParsesAllEntriesInOrder() throws {
        let playlist = try sample()
        XCTAssertEqual(playlist.channels.map(\.title), [
            "Örnek Haber HD", "Demo Spor, Canlı", "Kurmaca Müzik", "Test Radyo",
            "Hayali Belgesel", "Grupsuz Kanal", "Kurgu Film (2024)",
        ])
        XCTAssertEqual(playlist.skippedEntryCount, 0)
    }

    func testHeaderAttributesAndDedupedEPGURLs() throws {
        let playlist = try sample()
        XCTAssertEqual(playlist.headerAttributes["catchup"], "default")
        XCTAssertEqual(playlist.epgURLs.map(\.absoluteString), [
            "http://epg.example.com/guide.xml", "http://epg.example.com/backup.xml",
        ])
    }

    func testQuotedAttributesWithSpacesAndAllKnownKeys() throws {
        let c = try channel(sample(), titled: "Örnek Haber HD")
        XCTAssertEqual(c.tvgID, "ornek.haber")
        XCTAssertEqual(c.tvgName, "Örnek Haber")
        XCTAssertEqual(c.groupTitle, "Haber")
        XCTAssertEqual(c.channelNumber, 7)
        XCTAssertEqual(c.language, "Turkish")
        XCTAssertEqual(c.country, "TR")
        XCTAssertEqual(c.catchup, "append")
        XCTAssertEqual(c.catchupSource, "?utc={utc}&lutc={lutc}")
        XCTAssertEqual(c.logoURL?.absoluteString, "http://img.example.com/logos/ornek%20haber.png")
        XCTAssertEqual(c.duration, -1)
        XCTAssertEqual(c.kind, .live)
        XCTAssertEqual(c.container, .hls)
    }

    func testTitleContainingCommas() throws {
        let c = try channel(sample(), titled: "Demo Spor, Canlı")
        XCTAssertEqual(c.tvgID, "demo.spor")
    }

    func testEXTVLCOPTUserAgentAndReferrer() throws {
        let c = try channel(sample(), titled: "Demo Spor, Canlı")
        XCTAssertEqual(c.userAgent, "DemoPlayer/2.0 (Test)")
        XCTAssertEqual(c.referrer, "http://portal.example.com/")
        XCTAssertEqual(c.vlcOptions["http-user-agent"], "DemoPlayer/2.0 (Test)")
        XCTAssertEqual(c.httpHeaders, ["User-Agent": "DemoPlayer/2.0 (Test)", "Referer": "http://portal.example.com/"])
    }

    func testUnquotedAttributesAndKodiProps() throws {
        let c = try channel(sample(), titled: "Kurmaca Müzik")
        XCTAssertEqual(c.tvgID, "kurmaca.muzik")
        XCTAssertEqual(c.groupTitle, "Müzik")
        XCTAssertEqual(c.logoURL?.absoluteString, "http://img.example.com/muzik.png")
        XCTAssertEqual(c.duration, 0)
        XCTAssertEqual(c.kodiProperties["inputstream"], "inputstream.adaptive")
        XCTAssertEqual(c.kodiProperties["inputstream.adaptive.manifest_type"], "hls")
    }

    func testURLWithSpacesIsPercentEncoded() throws {
        let c = try channel(sample(), titled: "Kurmaca Müzik")
        XCTAssertEqual(c.streamURL.absoluteString, "http://stream.example.com/live/kurmaca%20muzik/playlist.m3u8")
    }

    func testAttributesWithoutCommaTitleFallBackToTvgName() throws {
        let c = try channel(sample(), titled: "Test Radyo")
        XCTAssertTrue(c.isRadio)
        XCTAssertEqual(c.container, .audio)
        XCTAssertEqual(c.groupTitle, "Radyo")
    }

    func testEXTGRPAppliesWhenGroupTitleMissing() throws {
        let c = try channel(sample(), titled: "Hayali Belgesel")
        XCTAssertEqual(c.groupTitle, "Belgesel")
    }

    func testPipeHeadersAreStrippedFromURL() throws {
        let c = try channel(sample(), titled: "Hayali Belgesel")
        XCTAssertEqual(c.streamURL.absoluteString, "http://stream.example.com/live/hayali-belgesel.m3u8")
        XCTAssertEqual(c.userAgent, "KodiLike/1.0")
        XCTAssertEqual(c.referrer, "http://ref.example.com/")
    }

    func testTrailingWhitespaceAndUngroupedTS() throws {
        let c = try channel(sample(), titled: "Grupsuz Kanal")
        XCTAssertEqual(c.streamURL.absoluteString, "http://stream.example.com/live/grupsuz.ts")
        XCTAssertNil(c.groupTitle)
        XCTAssertEqual(c.container, .mpegTS)
        XCTAssertFalse(c.container.isAVPlayerCompatible)
    }

    func testMovieKindAndEmptyAttributeBecomesNil() throws {
        let c = try channel(sample(), titled: "Kurgu Film (2024)")
        XCTAssertEqual(c.kind, .movie)
        XCTAssertNil(c.tvgID)
        XCTAssertEqual(c.duration, 7200)
        XCTAssertEqual(c.container, .mpeg4)
    }

    func testGroupsInFirstAppearanceOrderWithUngroupedLast() throws {
        let playlist = try sample()
        XCTAssertEqual(playlist.groups.map(\.name), ["Haber", "Spor", "Müzik", "Radyo", "Belgesel", "Filmler", nil])
        XCTAssertTrue(playlist.groups.last?.isUngrouped ?? false)
        let haber = try XCTUnwrap(playlist.groups.first)
        XCTAssertEqual(playlist.channels(in: haber).map(\.title), ["Örnek Haber HD"])
    }

    // MARK: Line endings / encodings

    func testCRLFAndUTF8BOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("#EXTM3U\r\n#EXTINF:-1 group-title=\"A\",Birinci\r\nhttp://a.example.com/1.m3u8\r\n\r\n#EXTINF:-1,İkinci\r\nhttp://a.example.com/2.m3u8\r\n".utf8))
        let playlist = try parser.parse(data: data)
        XCTAssertEqual(playlist.channels.map(\.title), ["Birinci", "İkinci"])
        XCTAssertEqual(playlist.channels[0].groupTitle, "A")
        XCTAssertEqual(playlist.channels[1].streamURL.absoluteString, "http://a.example.com/2.m3u8")
    }

    func testClassicMacLineEndings() throws {
        let text = "#EXTM3U\r#EXTINF:-1,Tek\rhttp://a.example.com/tek.m3u8\r"
        let playlist = try parser.parse(string: text)
        XCTAssertEqual(playlist.channels.map(\.title), ["Tek"])
    }

    func testNonUTF8BytesFallBackToLegacyEncoding() throws {
        var data = Data("#EXTM3U\n#EXTINF:-1,Caf".utf8)
        data.append(0xE9) // 'é' in Windows-1254 / ISO-8859-1, invalid as UTF-8
        data.append(Data("\nhttp://a.example.com/cafe.m3u8\n".utf8))
        let playlist = try parser.parse(data: data)
        XCTAssertEqual(playlist.channels.first?.title, "Café")
    }

    // MARK: Structure edge cases

    func testMissingHeaderIsAccepted() throws {
        let playlist = try parser.parse(string: "#EXTINF:-1,Başlıksız Liste\nhttp://a.example.com/x.m3u8\n")
        XCTAssertEqual(playlist.channels.count, 1)
        XCTAssertTrue(playlist.headerAttributes.isEmpty)
    }

    func testBareURLListUsesPathAsTitle() throws {
        let playlist = try parser.parse(string: "http://a.example.com/live/kanal-bir.m3u8\nhttp://a.example.com/live/kanal-iki.m3u8\n")
        XCTAssertEqual(playlist.channels.map(\.title), ["kanal-bir", "kanal-iki"])
    }

    func testCommentBetweenExtinfAndURLKeepsMetadata() throws {
        let text = "#EXTM3U\n#EXTINF:-1 tvg-id=\"x\",Yorumlu\n# a comment\n\n#EXT-X-UNKNOWN:1\nhttp://a.example.com/y.m3u8\n"
        let c = try XCTUnwrap(try parser.parse(string: text).channels.first)
        XCTAssertEqual(c.title, "Yorumlu")
        XCTAssertEqual(c.tvgID, "x")
    }

    func testEmptyTitleAfterCommaFallsBack() throws {
        let text = "#EXTINF:-1 tvg-name=\"Yedek İsim\",   \nhttp://a.example.com/z.m3u8\n"
        XCTAssertEqual(try parser.parse(string: text).channels.first?.title, "Yedek İsim")
    }

    func testInvalidURLIsSkippedAndCounted() throws {
        let text = "#EXTINF:-1,Bozuk\nnot a url\n#EXTINF:-1,Sağlam\nhttp://a.example.com/ok.m3u8\n"
        let playlist = try parser.parse(string: text)
        XCTAssertEqual(playlist.channels.map(\.title), ["Sağlam"])
        XCTAssertEqual(playlist.skippedEntryCount, 1)
    }

    func testRelativeURLResolvedAgainstBaseURL() throws {
        let base = URL(string: "http://lists.example.com/user/list.m3u")!
        let playlist = try parser.parse(string: "#EXTINF:-1,Göreli\nstreams/one.m3u8\n", baseURL: base)
        XCTAssertEqual(playlist.channels.first?.streamURL.absoluteString, "http://lists.example.com/user/streams/one.m3u8")
    }

    func testEmptyPlaylistThrows() {
        assertThrows(.emptyPlaylist) { try parser.parse(string: "#EXTM3U\n\n# nothing here\n") }
    }

    func testGzipDataRejected() {
        assertThrows(.compressedDataNotSupported) { try parser.parse(data: Data([0x1F, 0x8B, 0x08, 0x00])) }
    }

    // MARK: HLS rejection

    func testHLSMediaPlaylistIsRejected() throws {
        let data = try Fixture.data("hls_media.m3u8")
        assertThrows(.notAChannelList(.hlsMediaPlaylist)) { try parser.parse(data: data) }
    }

    func testHLSMasterPlaylistIsRejectedFromString() throws {
        let text = String(decoding: try Fixture.data("hls_master.m3u8"), as: UTF8.self)
        assertThrows(.notAChannelList(.hlsMediaPlaylist)) { try parser.parse(string: text) }
    }

    // MARK: Identity

    func testStableIDsSurviveReimportAndReordering() throws {
        let a = "#EXTINF:-1,Bir\nhttp://a.example.com/1.m3u8\n#EXTINF:-1,İki\nhttp://a.example.com/2.m3u8\n"
        let b = "#EXTM3U\n#EXTINF:-1 group-title=\"Yeni\",İki\nhttp://a.example.com/2.m3u8\n#EXTINF:-1,Bir\nhttp://a.example.com/1.m3u8\n"
        let first = try parser.parse(string: a).makeIndex()
        let second = try parser.parse(string: b).makeIndex()
        XCTAssertEqual(Set(first.keys), Set(second.keys))
        for (id, channel) in first {
            XCTAssertEqual(second[id]?.title, channel.title)
        }
        XCTAssertEqual(first.keys.first?.count, 16)
    }

    func testDuplicateEntriesGetDistinctDeterministicIDs() throws {
        let text = "#EXTINF:-1,Aynı\nhttp://a.example.com/s.m3u8\n#EXTINF:-1,Aynı\nhttp://a.example.com/s.m3u8\n"
        let ids1 = try parser.parse(string: text).channels.map(\.id)
        let ids2 = try parser.parse(string: text).channels.map(\.id)
        XCTAssertEqual(ids1.count, 2)
        XCTAssertNotEqual(ids1[0], ids1[1])
        XCTAssertEqual(ids1, ids2)
        XCTAssertEqual(ids1[1], ids1[0] + "-2")
    }

    // MARK: Attribute parser

    func testAttributeParserHandlesQuotesCaseAndUnterminatedValues() {
        let r1 = M3UAttributeParser.parse(" TVG-ID='single q' group-title=\"a, b\" bare x=1,Başlık, ikinci")
        XCTAssertEqual(r1.attributes["tvg-id"], "single q")
        XCTAssertEqual(r1.attributes["group-title"], "a, b")
        XCTAssertEqual(r1.attributes["x"], "1")
        XCTAssertNil(r1.attributes["bare"])
        XCTAssertEqual(r1.trailingText, "Başlık, ikinci")

        let r2 = M3UAttributeParser.parse(" tvg-name=\"Açık tırnak,Başlık")
        XCTAssertEqual(r2.attributes["tvg-name"], "Açık tırnak")
        XCTAssertEqual(r2.trailingText, "Başlık")
    }

    func testExtinfDurationVariants() {
        XCTAssertEqual(M3UParser.parseExtinf(Array("-1,T".utf8)[...]).duration, -1)
        XCTAssertEqual(M3UParser.parseExtinf(Array(" 12.5 tvg-id=\"a\",T".utf8)[...]).duration, 12.5)
        XCTAssertNil(M3UParser.parseExtinf(Array("tvg-id=\"a\",T".utf8)[...]).duration)
    }

    // MARK: Performance

    func testLargePlaylistOf50kEntriesParses() throws {
        let count = 50_000
        var text = "#EXTM3U url-tvg=\"http://epg.example.com/guide.xml\"\n"
        text.reserveCapacity(count * 170)
        for i in 0..<count {
            text += "#EXTINF:-1 tvg-id=\"kanal\(i).example\" tvg-name=\"Kanal \(i)\" tvg-logo=\"http://img.example.com/\(i).png\" group-title=\"Grup \(i % 50)\",Kanal \(i)\n"
            text += "http://stream.example.com/live/\(i).m3u8\n"
        }
        let data = Data(text.utf8)
        let started = Date()
        let playlist = try parser.parse(data: data)
        let elapsed = Date().timeIntervalSince(started)
        print("[perf] parsed \(count) entries (\(data.count / 1024) KiB) in \(String(format: "%.3f", elapsed)) s")
        XCTAssertEqual(playlist.channels.count, count)
        XCTAssertEqual(playlist.groups.count, 50)
        XCTAssertEqual(Set(playlist.channels.map(\.id)).count, count)
        // Lenient bound: debug builds on CI/Windows are far slower than release on device.
        XCTAssertLessThan(elapsed, 30)
    }
}
