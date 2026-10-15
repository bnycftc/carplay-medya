import Foundation
import XCTest
@testable import CarMediaKit

final class CarVideoDiagnosisTests: XCTestCase {
    private let connected = Date(timeIntervalSinceReferenceDate: 800_000_000.25)

    private func snapshot(
        systemSupportsAPI: Bool = true,
        carSupportsVideo: Bool? = true,
        playedVideoItem: Bool = false,
        externalPlaybackSeen: Bool = false
    ) -> CarVideoSnapshot {
        CarVideoSnapshot(
            connectedAt: connected,
            systemSupportsAPI: systemSupportsAPI,
            carSupportsVideo: carSupportsVideo,
            playedVideoItem: playedVideoItem,
            externalPlaybackSeen: externalPlaybackSeen
        )
    }

    func testNoSnapshot() {
        XCTAssertEqual(CarVideoDiagnosis(snapshot: nil, settingOn: true), .notConnectedYet)
        XCTAssertEqual(CarVideoDiagnosis(snapshot: nil, settingOn: false), .notConnectedYet)
    }

    func testSystemTooOld() {
        let s = snapshot(systemSupportsAPI: false, carSupportsVideo: nil)
        XCTAssertEqual(CarVideoDiagnosis(snapshot: s, settingOn: true), .systemTooOld)
        XCTAssertEqual(CarVideoDiagnosis(snapshot: s, settingOn: false), .systemTooOld)
    }

    func testCarHasNoVideo() {
        XCTAssertEqual(CarVideoDiagnosis(snapshot: snapshot(carSupportsVideo: nil), settingOn: true), .carHasNoVideo)
        XCTAssertEqual(CarVideoDiagnosis(snapshot: snapshot(carSupportsVideo: false), settingOn: true), .carHasNoVideo,
                       "without car support the setting cannot help")
        XCTAssertEqual(CarVideoDiagnosis(snapshot: snapshot(carSupportsVideo: false), settingOn: false), .carHasNoVideo)
    }

    func testSettingOff() {
        XCTAssertEqual(CarVideoDiagnosis(snapshot: snapshot(), settingOn: false), .settingOff)
        XCTAssertEqual(CarVideoDiagnosis(snapshot: snapshot(playedVideoItem: true), settingOn: false), .settingOff)
    }

    func testReady() {
        XCTAssertEqual(CarVideoDiagnosis(snapshot: snapshot(), settingOn: true), .ready)
    }

    func testVideoNotShown() {
        XCTAssertEqual(CarVideoDiagnosis(snapshot: snapshot(playedVideoItem: true), settingOn: true), .videoNotShown)
    }

    func testVideoShown() {
        XCTAssertEqual(CarVideoDiagnosis(snapshot: snapshot(externalPlaybackSeen: true), settingOn: true), .videoShown)
        XCTAssertEqual(
            CarVideoDiagnosis(snapshot: snapshot(playedVideoItem: true, externalPlaybackSeen: true), settingOn: true),
            .videoShown
        )
    }

    func testSampleReportsChange() {
        var s = snapshot(carSupportsVideo: nil)
        XCTAssertTrue(s.sample(carSupportsVideo: false))
        XCTAssertEqual(s.carSupportsVideo, false)
        XCTAssertFalse(s.sample(carSupportsVideo: false), "same value is not a change")
        XCTAssertTrue(s.sample(carSupportsVideo: true))
        XCTAssertEqual(s.carSupportsVideo, true)
    }

    func testMarkVideoPlayed() {
        var s = snapshot()
        XCTAssertTrue(s.markVideoPlayed())
        XCTAssertTrue(s.playedVideoItem)
        XCTAssertFalse(s.markVideoPlayed(), "already recorded")
    }

    func testMarkExternalPlaybackOnlyRecordsTrue() {
        var s = snapshot()
        XCTAssertFalse(s.markExternalPlayback(false))
        XCTAssertFalse(s.externalPlaybackSeen)
        XCTAssertTrue(s.markExternalPlayback(true))
        XCTAssertTrue(s.externalPlaybackSeen)
        XCTAssertFalse(s.markExternalPlayback(true), "already recorded")
        XCTAssertFalse(s.markExternalPlayback(false), "false never clears the flag")
        XCTAssertTrue(s.externalPlaybackSeen)
    }

    func testMarkExternalPlaybackIgnoredAfterClose() {
        var s = snapshot()
        XCTAssertTrue(s.isConnected)
        s.close(at: connected.addingTimeInterval(60))
        XCTAssertFalse(s.isConnected)
        XCTAssertFalse(s.markExternalPlayback(true), "phone-only AirPlay after leaving the car does not count")
        XCTAssertFalse(s.externalPlaybackSeen)
    }

    func testJSONRoundTrip() throws {
        var s = snapshot(carSupportsVideo: true, playedVideoItem: true)
        s.markExternalPlayback(true)
        s.close(at: connected.addingTimeInterval(125.5))
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(CarVideoSnapshot.self, from: data)
        XCTAssertEqual(decoded.connectedAt.timeIntervalSinceReferenceDate,
                       s.connectedAt.timeIntervalSinceReferenceDate, accuracy: 0.001)
        let decodedEnd = try XCTUnwrap(decoded.disconnectedAt)
        let originalEnd = try XCTUnwrap(s.disconnectedAt)
        XCTAssertEqual(decodedEnd.timeIntervalSinceReferenceDate, originalEnd.timeIntervalSinceReferenceDate, accuracy: 0.001)
        XCTAssertEqual(decoded.systemSupportsAPI, true)
        XCTAssertEqual(decoded.carSupportsVideo, true)
        XCTAssertTrue(decoded.playedVideoItem)
        XCTAssertTrue(decoded.externalPlaybackSeen)

        let unknown = snapshot(systemSupportsAPI: false, carSupportsVideo: nil)
        let unknownDecoded = try JSONDecoder().decode(CarVideoSnapshot.self, from: try JSONEncoder().encode(unknown))
        XCTAssertNil(unknownDecoded.carSupportsVideo)
        XCTAssertNil(unknownDecoded.disconnectedAt)
        XCTAssertFalse(unknownDecoded.systemSupportsAPI)
    }
}
