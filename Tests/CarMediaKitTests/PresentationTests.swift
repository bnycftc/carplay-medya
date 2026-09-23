import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CarMediaCore
@testable import CarMediaKit

final class EPGPresenterTests: XCTestCase {
    private let presenter = EPGPresenter(timeZone: TimeZone(identifier: "UTC")!)
    private let base = Date(timeIntervalSince1970: 1_893_456_000) // 2030-01-01 00:00 UTC

    private func store() -> EPGStore {
        EPGStore(
            channels: [EPGChannel(id: "haber.example", displayNames: ["Haber Bir"])],
            programmes: [
                Programme(channelID: "haber.example", start: base.addingTimeInterval(20 * 3600),
                          stop: base.addingTimeInterval(21 * 3600), title: "Akşam"),
                Programme(channelID: "haber.example", start: base.addingTimeInterval(21 * 3600),
                          stop: base.addingTimeInterval(22 * 3600 + 30 * 60), title: "Gece"),
            ]
        )
    }

    func testNowAndNextLines() throws {
        let channel = Sample.channel("Haber Bir", tvgID: "haber.example")
        let at = base.addingTimeInterval(20 * 3600 + 15 * 60)
        let summary = try XCTUnwrap(presenter.summary(for: channel, in: store(), at: at))
        XCTAssertEqual(summary.nowLine, "20:00\u{2013}21:00 Akşam")
        XCTAssertEqual(summary.nextLine, "21:00 Gece")
        XCTAssertEqual(summary.progress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(summary.minutesRemaining, 45)
    }

    func testMatchesByDisplayNameAndHandlesGaps() throws {
        let byName = Sample.channel("HABER BİR")
        let beforeFirst = base.addingTimeInterval(19 * 3600)
        let summary = try XCTUnwrap(presenter.summary(for: byName, in: store(), at: beforeFirst))
        XCTAssertNil(summary.now)
        XCTAssertNil(summary.nowLine)
        XCTAssertEqual(summary.progress, 0)
        XCTAssertEqual(summary.nextLine, "20:00 Akşam")

        let afterLast = base.addingTimeInterval(23 * 3600)
        XCTAssertNil(presenter.summary(for: byName, in: store(), at: afterLast))
        XCTAssertNil(presenter.summary(for: Sample.channel("Bilinmeyen"), in: store(), at: beforeFirst))
    }

    func testMinutesRemainingRoundsUpAndNeverNegative() {
        XCTAssertEqual(EPGPresenter.minutesRemaining(until: base.addingTimeInterval(61), from: base), 2)
        XCTAssertEqual(EPGPresenter.minutesRemaining(until: base, from: base.addingTimeInterval(10)), 0)
        XCTAssertEqual(presenter.timeText(base.addingTimeInterval(9 * 3600 + 5 * 60)), "09:05")
    }
}

final class SourceDraftTests: XCTestCase {
    func testM3UInputIsNormalizedAndValidated() throws {
        let source = try SourceDraft.m3uSource(id: "a", name: " ", urlText: " lists.example.com/my list.m3u ")
        guard case .m3uURL(_, let name, let url, let agent) = source else { return XCTFail("wrong case") }
        XCTAssertEqual(name, "lists.example.com")
        XCTAssertEqual(url.scheme, "http")
        XCTAssertTrue(url.absoluteString.hasSuffix("my%20list.m3u"))
        XCTAssertNil(agent)

        for bad in ["", "ftp://lists.example.com/a.m3u", "http://"] {
            XCTAssertThrowsError(try SourceDraft.m3uSource(name: "x", urlText: bad), bad) { error in
                XCTAssertEqual(error as? UserFacingError, .invalidAddress)
            }
        }
    }

    func testXtreamAndLocalDrafts() throws {
        XCTAssertThrowsError(try SourceDraft.xtreamCredentials(server: "panel.example.com", username: "u", password: ""))
        let creds = try SourceDraft.xtreamCredentials(server: "http://panel.example.com:8080/get.php?username=u", username: "u", password: "p")
        let source = SourceDraft.xtreamSource(id: "x", name: "", credentials: creds)
        XCTAssertEqual(source.name, "panel.example.com")
        XCTAssertTrue(source.isXtream)
        XCTAssertFalse(source.isPlaylistPersistable)
        let json = String(decoding: try JSONEncoder().encode(source), as: UTF8.self)
        XCTAssertFalse(json.contains("\"p\""), "the password is not part of the source")

        XCTAssertEqual(SourceDraft.localFileSource(id: "l", fileName: "Yaz Tatili.mp4", bookmark: Data()).name, "Yaz Tatili")
        XCTAssertNotEqual(SourceDraft.makeID(), SourceDraft.makeID())
    }

    func testXtreamAccountSummary() throws {
        let json = #"{"user_info":{"auth":1,"status":"Active","exp_date":"1893456000","is_trial":"0","active_cons":"2","max_connections":"2","allowed_output_formats":["ts"]}}"#
        let info = try JSONDecoder().decode(XtreamAccountInfo.self, from: Data(json.utf8))
        let summary = XtreamAccountSummary(info: info)
        XCTAssertEqual(summary.status, .active)
        XCTAssertFalse(summary.supportsHLS)
        XCTAssertTrue(summary.isAtConnectionLimit)
        let tenDaysBefore = Date(timeIntervalSince1970: 1_893_456_000 - 10 * 86_400)
        XCTAssertEqual(summary.daysRemaining(at: tenDaysBefore), 10)
        XCTAssertFalse(summary.isExpired(at: tenDaysBefore))
        XCTAssertTrue(summary.isExpired(at: Date(timeIntervalSince1970: 1_893_456_000)))

        let other = try JSONDecoder().decode(XtreamAccountInfo.self, from: Data(#"{"user_info":{"auth":1,"status":"Paused"}}"#.utf8))
        XCTAssertEqual(XtreamAccountSummary(info: other).status, .other("Paused"))
        XCTAssertNil(XtreamAccountSummary(info: other).daysRemaining(at: Date()))
    }
}

final class ListCappingTests: XCTestCase {
    func testCapsSectionsAndItemsAndDropsEmptySections() {
        let sections = [
            ListSection(header: "A", items: [1, 2, 3]),
            ListSection(header: "Boş", items: []),
            ListSection(header: "B", items: [4, 5]),
            ListSection(header: "C", items: [6]),
        ]
        let capped = ListCapping.cap(sections, maxSections: 2, maxItems: 4)
        XCTAssertEqual(capped.sections, [ListSection(header: "A", items: [1, 2, 3]), ListSection(header: "B", items: [4])])
        XCTAssertEqual(capped.itemCount, 4)
        XCTAssertEqual(capped.omittedItemCount, 2)

        XCTAssertTrue(ListCapping.cap(sections, maxSections: 0, maxItems: 12).sections.isEmpty)
        XCTAssertEqual(ListCapping.cap(sections, maxSections: 10, maxItems: 100).omittedItemCount, 0)
        XCTAssertEqual(ListCapping.cap(Array(1...20), maxItems: 12).count, 12)
    }
}

final class UserFacingErrorTests: XCTestCase {
    func testClassification() {
        XCTAssertEqual(UserFacingError.from(CarMediaError.notAChannelList(.hlsMediaPlaylist)), .mediaStreamNotList)
        XCTAssertEqual(UserFacingError.from(CarMediaError.notAChannelList(.unknown)), .notAChannelList)
        XCTAssertEqual(UserFacingError.from(CarMediaError.authenticationFailed), .authentication)
        XCTAssertEqual(UserFacingError.from(CarMediaError.transport("x")), .network)
        XCTAssertEqual(UserFacingError.from(URLError(.timedOut)), .network)
        XCTAssertEqual(UserFacingError.from(SourceStoreError.missingPassword), .missingPassword)
        XCTAssertEqual(UserFacingError.from(UserFacingError.unsupported(.udp)), .unsupported(.udp))
        let wrapped = NSError(domain: "AVFoundationErrorDomain", code: -11800,
                              userInfo: [NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: -1001)])
        XCTAssertEqual(UserFacingError.from(wrapped), .network)
        struct Other: Error {}
        XCTAssertEqual(UserFacingError.from(Other()), .unknown)
    }

    func testCodableRoundTrip() throws {
        let values: [UserFacingError] = [.httpStatus(503), .unsupported(.matroska), .network]
        let decoded = try JSONDecoder().decode([UserFacingError].self, from: JSONEncoder().encode(values))
        XCTAssertEqual(decoded, values)
    }
}
