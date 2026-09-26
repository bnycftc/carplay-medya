import Foundation
import XCTest
@testable import CarMediaCore

final class CatchupURLBuilderTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    // 2026-09-26 18:30:00 UTC
    private let start = Date(timeIntervalSince1970: 1_790_447_400)
    private var end: Date { start.addingTimeInterval(45 * 60) }
    private var now: Date { start.addingTimeInterval(3 * 3600) }

    private func channel(_ url: String, catchup: String?, source: String? = nil, days: String? = nil) -> Channel {
        var attributes: [String: String] = [:]
        if let days { attributes["catchup-days"] = days }
        return Channel(
            id: "c1", title: "Kanal", streamURL: URL(string: url)!,
            catchup: catchup, catchupSource: source, attributes: attributes
        )
    }

    func testXtreamTimeshiftUsesHLSAndServerTimeZone() throws {
        let live = channel("http://tv.example.com:8080/live/demo/p%40ss/101.m3u8", catchup: "xc")
        let istanbul = TimeZone(identifier: "Europe/Istanbul")!
        let url = try XCTUnwrap(CatchupURLBuilder.url(for: live, start: start, end: end, now: now, timeZone: istanbul))
        XCTAssertEqual(url.absoluteString, "http://tv.example.com:8080/timeshift/demo/p%40ss/45/2026-09-26:21-30/101.m3u8")
    }

    func testXtreamTimeshiftKeepsPathPrefixAndRoundsMinutesUp() throws {
        let live = channel("https://tv.example.com/panel/live/u/p/7.ts", catchup: "xc")
        let url = try XCTUnwrap(CatchupURLBuilder.url(
            for: live, start: start, end: start.addingTimeInterval(61), now: now, timeZone: utc))
        XCTAssertEqual(url.absoluteString, "https://tv.example.com/panel/timeshift/u/p/2/2026-09-26:18-30/7.m3u8")
    }

    func testXtreamModeNeedsLivePath() {
        let other = channel("http://tv.example.com/stream/101.m3u8", catchup: "xc")
        XCTAssertNil(CatchupURLBuilder.url(for: other, start: start, end: end, now: now))
    }

    func testDefaultTemplateSubstitutesPlaceholders() throws {
        let c = channel("http://tv.example.com/live/index.m3u8", catchup: "default",
                        source: "http://arc.example.com/k/{Y}{m}{d}/{H}{M}.m3u8?s=${start}&e={utcend}&d={duration}&o=${offset}")
        let url = try XCTUnwrap(CatchupURLBuilder.url(for: c, start: start, end: end, now: now, timeZone: utc))
        XCTAssertEqual(url.absoluteString,
                       "http://arc.example.com/k/20260926/1830.m3u8?s=1790447400&e=1790450100&d=2700&o=10800")
    }

    func testFormattedPlaceholders() {
        let context = CatchupURLBuilder.Context(start: start, end: end, now: now, timeZone: utc)
        XCTAssertEqual(CatchupURLBuilder.substitute("{utc:Y-m-d H:M:S}|${end:YmdHMS}", context: context),
                       "2026-09-26 18:30:00|20260926191500")
        XCTAssertEqual(CatchupURLBuilder.substitute("{unknown}${x}", context: context), "{unknown}${x}")
    }

    func testAppendAndShiftModes() throws {
        let append = channel("http://tv.example.com/ch/1.m3u8", catchup: "append", source: "?utc={utc}&lutc={lutc}")
        XCTAssertEqual(CatchupURLBuilder.url(for: append, start: start, end: end, now: now)?.absoluteString,
                       "http://tv.example.com/ch/1.m3u8?utc=1790447400&lutc=1790458200")
        let shift = channel("http://tv.example.com/ch/1.m3u8?token=a", catchup: "shift")
        XCTAssertEqual(CatchupURLBuilder.url(for: shift, start: start, end: end, now: now)?.absoluteString,
                       "http://tv.example.com/ch/1.m3u8?token=a&utc=1790447400&lutc=1790458200")
    }

    func testFlussonicRenamesPlaylist() throws {
        let c = channel("http://fs.example.com/kanal/index.m3u8?token=x", catchup: "flussonic")
        XCTAssertEqual(CatchupURLBuilder.url(for: c, start: start, end: end, now: now)?.absoluteString,
                       "http://fs.example.com/kanal/index-1790447400-2700.m3u8?token=x")
        let ts = channel("http://fs.example.com/kanal/mpegts", catchup: "flussonic")
        XCTAssertNil(CatchupURLBuilder.url(for: ts, start: start, end: end, now: now))
    }

    func testUnknownOrMissingModes() {
        XCTAssertNil(CatchupURLBuilder.url(for: channel("http://a.example.com/1.m3u8", catchup: nil),
                                           start: start, end: end, now: now))
        XCTAssertNil(CatchupURLBuilder.url(for: channel("http://a.example.com/1.m3u8", catchup: "vod"),
                                           start: start, end: end, now: now))
        XCTAssertFalse(CatchupURLBuilder.supportsCatchup(channel("http://a.example.com/1.m3u8", catchup: "default")))
        XCTAssertNil(CatchupURLBuilder.url(for: channel("http://a.example.com/live/u/p/1.m3u8", catchup: "xc"),
                                           start: end, end: start, now: now))
    }

    func testAvailabilityRespectsArchiveDepthAndTime() {
        let c = channel("http://a.example.com/live/u/p/1.m3u8", catchup: "xc", days: "2")
        XCTAssertTrue(CatchupURLBuilder.isAvailable(for: c, programmeStart: start, programmeEnd: end, now: now))
        let old = start.addingTimeInterval(-3 * 86_400)
        XCTAssertFalse(CatchupURLBuilder.isAvailable(for: c, programmeStart: old, programmeEnd: old.addingTimeInterval(600), now: now))
        XCTAssertFalse(CatchupURLBuilder.isAvailable(for: c, programmeStart: now.addingTimeInterval(60),
                                                     programmeEnd: now.addingTimeInterval(600), now: now))
        XCTAssertEqual(CatchupURLBuilder.archiveDays(of: channel("http://a.example.com/1", catchup: "xc")),
                       CatchupURLBuilder.defaultArchiveDays)
    }
}

final class GzipTests: XCTestCase {
    /// `printf 'hello\n' | gzip -n` with FNAME added by hand ("a\0").
    private let sample: [UInt8] = [
        0x1F, 0x8B, 0x08, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x61, 0x00,
        0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0xE7, 0x02, 0x00,
        0x20, 0x30, 0x3A, 0x36, 0x06, 0x00, 0x00, 0x00,
    ]

    func testExtractsRawDeflateAndSize() throws {
        let member = try Gzip.member(of: Data(sample))
        XCTAssertEqual([UInt8](member.deflate), [0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0xE7, 0x02, 0x00])
        XCTAssertEqual(member.uncompressedSize, 6)
    }

    func testRejectsNonGzipAndTruncatedData() {
        XCTAssertThrowsError(try Gzip.member(of: Data("<tv></tv>".utf8)))
        XCTAssertThrowsError(try Gzip.member(of: Data(sample.prefix(15))))
        var badName = sample
        badName.removeSubrange(11...) // FNAME never terminated
        badName += [0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69]
        XCTAssertThrowsError(try Gzip.member(of: Data(badName)))
    }
}

final class XtreamCatchupMappingTests: XCTestCase {
    func testArchiveChannelsGetCatchupDays() throws {
        let client = XtreamClient(
            credentials: try XtreamCredentials(baseURL: "http://iptv.example.com:8080", username: "demo", password: "pw"),
            transport: StubTransport.xtream(fixtures: [:])
        )
        let streams = try JSONDecoder().decode([XtreamLiveStream].self, from: Data("""
        [{"stream_id": 101, "name": "A", "tv_archive": 1, "tv_archive_duration": "3"},
         {"stream_id": 102, "name": "B", "tv_archive": 0}]
        """.utf8))
        let channels = client.channels(from: streams)
        XCTAssertEqual(channels[0].catchup, "xc")
        XCTAssertEqual(channels[0].attributes["catchup-days"], "3")
        XCTAssertNil(channels[1].catchup)
        XCTAssertNil(channels[1].attributes["catchup-days"])
        XCTAssertEqual(CatchupURLBuilder.archiveDays(of: channels[0]), 3)
    }
}
