import Foundation
import XCTest
@testable import CarMediaCore

final class XMLTVParserTests: XCTestCase {
    /// 2026-09-22 15:00:00 UTC (= 18:00 +0300).
    private let t1500 = Date(timeIntervalSince1970: 1_790_089_200)

    private func document() throws -> XMLTVDocument {
        try XMLTVParser.parse(data: Fixture.data("epg.xml"))
    }

    func testChannelsParsed() throws {
        let doc = try document()
        XCTAssertEqual(doc.channels.map(\.id), ["ornek.haber", "Demo.Spor"])
        XCTAssertEqual(doc.channels[0].displayNames, ["Örnek Haber", "Sample News"])
        XCTAssertEqual(doc.channels[0].iconURL?.absoluteString, "http://img.example.com/logos/ornek-haber.png")
        XCTAssertNil(doc.channels[1].iconURL)
        XCTAssertNil(doc.parseError)
    }

    func testProgrammeFieldsAndSkips() throws {
        let doc = try document()
        XCTAssertEqual(doc.programmes.count, 4)
        XCTAssertEqual(doc.skippedProgrammeCount, 2) // unparsable start + missing channel
        let first = doc.programmes[0]
        XCTAssertEqual(first.channelID, "ornek.haber")
        XCTAssertEqual(first.title, "Akşam Bülteni") // first <title> wins
        XCTAssertEqual(first.subtitle, "Bölüm 12")
        XCTAssertEqual(first.description, "Günün özeti & hava durumu.")
        XCTAssertEqual(first.categories, ["Haber", "Güncel"])
        XCTAssertEqual(first.episodeNumber, "S01E12") // onscreen preferred over xmltv_ns
        XCTAssertEqual(first.iconURL?.absoluteString, "http://img.example.com/epg/aksam.png")
        XCTAssertEqual(doc.programmes[1].title, "Gece Kuşağı") // CDATA
    }

    func testTimezoneOffsetsAndMissingZone() throws {
        let doc = try document()
        XCTAssertEqual(doc.programmes[0].start, t1500)
        XCTAssertEqual(doc.programmes[0].stop, t1500.addingTimeInterval(3600))
        // "20260922150000" without zone is UTC.
        XCTAssertEqual(doc.programmes[3].start, t1500)
        XCTAssertEqual(doc.programmes[3].stop, t1500.addingTimeInterval(7200))
    }

    func testMalformedDocumentThrows() {
        assertThrows(.invalidXMLTV("missing <tv> root element")) {
            try XMLTVParser.parse(data: Data("<?xml version=\"1.0\"?><other/>".utf8))
        }
        XCTAssertThrowsError(try XMLTVParser.parse(data: Data("this is not xml".utf8))) { error in
            guard case CarMediaError.invalidXMLTV = error else { return XCTFail("unexpected \(error)") }
        }
    }

    func testTruncatedDocumentKeepsWhatWasParsed() throws {
        let xml = """
        <tv><channel id="a"><display-name>A</display-name></channel>
        <programme start="20260922150000 +0000" stop="20260922160000 +0000" channel="a"><title>Tam</title></programme>
        <programme start="20260922160000 +0000" stop="20260922170000 +0000" channel="a"><title>Yar
        """
        let doc = try XMLTVParser.parse(data: Data(xml.utf8))
        XCTAssertEqual(doc.channels.count, 1)
        XCTAssertEqual(doc.programmes.map(\.title), ["Tam"])
        XCTAssertNotNil(doc.parseError)
    }

    func testGzipIsRejected() {
        assertThrows(.compressedDataNotSupported) { try XMLTVParser.parse(data: Data([0x1F, 0x8B, 0x08])) }
    }

    func testStreamingFileParseWithCallbacks() throws {
        var channelIDs: [String] = []
        var titles: [String] = []
        let summary = try XMLTVParser.parse(
            fileURL: Fixture.url("epg.xml"),
            onChannel: { channelIDs.append($0.id) },
            onProgramme: { titles.append($0.title) }
        )
        XCTAssertEqual(channelIDs, ["ornek.haber", "Demo.Spor"])
        XCTAssertEqual(titles, ["Akşam Bülteni", "Gece Kuşağı", "Son Program", "Maç Özeti"])
        XCTAssertEqual(summary, XMLTVParseSummary(channelCount: 2, programmeCount: 4, skippedProgrammeCount: 2, parseError: nil))
    }

    func testFileParseCollectsDocument() throws {
        let doc = try XMLTVParser.parse(fileURL: Fixture.url("epg.xml"))
        XCTAssertEqual(doc.programmes.count, 4)
    }
}

final class EPGStoreTests: XCTestCase {
    private let t1500 = Date(timeIntervalSince1970: 1_790_089_200)

    private func store() throws -> EPGStore {
        try XMLTVParser.parse(data: Fixture.data("epg.xml")).makeStore()
    }

    func testCurrentAndNext() throws {
        let s = try store()
        let at1530 = t1500.addingTimeInterval(1800)
        XCTAssertEqual(s.current(for: "ornek.haber", at: at1530)?.title, "Akşam Bülteni")
        XCTAssertEqual(s.next(for: "ornek.haber", at: at1530)?.title, "Gece Kuşağı")
        // Exactly at a boundary the new programme is current.
        XCTAssertEqual(s.current(for: "ornek.haber", at: t1500.addingTimeInterval(3600))?.title, "Gece Kuşağı")
        XCTAssertEqual(s.current(for: "ornek.haber", at: at1530)?.progress(at: at1530), 0.5)
    }

    func testNoCurrentBeforeFirstOrAfterLast() throws {
        let s = try store()
        XCTAssertNil(s.current(for: "ornek.haber", at: t1500.addingTimeInterval(-60)))
        XCTAssertEqual(s.next(for: "ornek.haber", at: t1500.addingTimeInterval(-60))?.title, "Akşam Bülteni")
        let late = t1500.addingTimeInterval(6 * 3600)
        XCTAssertNil(s.current(for: "ornek.haber", at: late))
        XCTAssertNil(s.next(for: "ornek.haber", at: late))
        XCTAssertNil(s.current(for: "unknown.channel", at: t1500))
    }

    func testMissingStopFilledWithFallbackDuration() throws {
        let last = try XCTUnwrap(try store().programmes(for: "ornek.haber").last)
        XCTAssertEqual(last.title, "Son Program")
        XCTAssertEqual(last.duration, EPGStore.fallbackDuration)
    }

    func testProgrammesInRange() throws {
        let s = try store()
        let range = t1500.addingTimeInterval(3000)..<t1500.addingTimeInterval(10_000)
        XCTAssertEqual(s.programmes(for: "ornek.haber", in: range).map(\.title), ["Akşam Bülteni", "Gece Kuşağı", "Son Program"])
        let narrow = t1500.addingTimeInterval(3600)..<t1500.addingTimeInterval(3601)
        XCTAssertEqual(s.programmes(for: "ornek.haber", in: narrow).map(\.title), ["Gece Kuşağı"])
    }

    func testResolveChannelIDFromM3UChannel() throws {
        let s = try store()
        XCTAssertEqual(s.resolveChannelID(tvgID: "ornek.haber"), "ornek.haber")
        XCTAssertEqual(s.resolveChannelID(tvgID: "demo.spor"), "Demo.Spor") // case-insensitive
        XCTAssertEqual(s.resolveChannelID(tvgID: nil, tvgName: nil, title: "ÖRNEK  haber"), "ornek.haber") // display name
        XCTAssertEqual(s.resolveChannelID(tvgID: "missing", title: "Sample News"), "ornek.haber")
        XCTAssertNil(s.resolveChannelID(tvgID: "missing", title: "Yok Böyle Kanal"))

        let m3u = try M3UParser().parse(string: "#EXTINF:-1 tvg-id=\"DEMO.SPOR\",Demo Spor\nhttp://a.example.com/s.m3u8\n")
        let channel = try XCTUnwrap(m3u.channels.first)
        let id = try XCTUnwrap(s.resolveChannelID(for: channel))
        XCTAssertEqual(s.current(for: id, at: t1500.addingTimeInterval(60))?.title, "Maç Özeti")
    }

    func testSortingDeduplicationAndPrune() {
        let base = t1500
        let p = { (offset: TimeInterval, title: String) in
            Programme(channelID: "c", start: base.addingTimeInterval(offset), stop: base.addingTimeInterval(offset + 600), title: title)
        }
        var s = EPGStore(programmes: [p(1200, "C"), p(0, "A"), p(600, "B"), p(0, "A-dup")])
        XCTAssertEqual(s.programmes(for: "c").map(\.title), ["A", "B", "C"])
        XCTAssertEqual(s.programmeCount, 3)
        s.add(programmes: [p(1800, "D")])
        XCTAssertEqual(s.programmes(for: "c").map(\.title), ["A", "B", "C", "D"])
        s.prune(before: base.addingTimeInterval(1300))
        XCTAssertEqual(s.programmes(for: "c").map(\.title), ["C", "D"])
    }
}

final class DateParsingTests: XCTestCase {
    func testXMLTVFormats() {
        let expected = Date(timeIntervalSince1970: 1_790_089_200) // 2026-09-22 15:00:00Z
        XCTAssertEqual(DateParsing.xmltv("20260922150000 +0000"), expected)
        XCTAssertEqual(DateParsing.xmltv("20260922180000 +0300"), expected)
        XCTAssertEqual(DateParsing.xmltv("20260922180000 +03:00"), expected)
        XCTAssertEqual(DateParsing.xmltv("20260922100000 -0500"), expected)
        XCTAssertEqual(DateParsing.xmltv("20260922150000"), expected)
        XCTAssertEqual(DateParsing.xmltv("20260922150000Z"), expected)
        XCTAssertEqual(DateParsing.xmltv("202609221500"), expected)
    }

    func testInvalidDatesRejected() {
        XCTAssertNil(DateParsing.xmltv(""))
        XCTAssertNil(DateParsing.xmltv("20261322150000"))
        XCTAssertNil(DateParsing.xmltv("20260230150000"))
        XCTAssertNil(DateParsing.xmltv("2026092215"))
        XCTAssertNil(DateParsing.xmltv("20260922150000 CEST"))
        XCTAssertNotNil(DateParsing.xmltv("20280229000000")) // leap day
    }

    func testUnixAndXtreamDateTimes() {
        XCTAssertEqual(DateParsing.unixTimestamp("1790089200"), Date(timeIntervalSince1970: 1_790_089_200))
        XCTAssertNil(DateParsing.unixTimestamp(""))
        XCTAssertNil(DateParsing.unixTimestamp(nil))
        XCTAssertEqual(DateParsing.xtreamDateTime("2026-09-22 15:00:00"), Date(timeIntervalSince1970: 1_790_089_200))
    }
}
