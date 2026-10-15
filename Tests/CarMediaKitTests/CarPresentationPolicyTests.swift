import Foundation
import XCTest
import CarMediaCore
@testable import CarMediaKit

final class CarPresentationPolicyTests: XCTestCase {
    func testDefaults() {
        let policy = CarPresentationPolicy()
        XCTAssertFalse(policy.carSupportsVideo, "before iOS 27 the car never supports video")
        XCTAssertFalse(policy.userAllowsVideoInCar, "video on the car display is off until the user turns it on")
        XCTAssertFalse(policy.videoAvailable)
    }

    func testVideoAvailableTruthTable() {
        for car in [false, true] {
            for user in [false, true] {
                let policy = CarPresentationPolicy(carSupportsVideo: car, userAllowsVideoInCar: user)
                XCTAssertEqual(policy.videoAvailable, car && user, "car=\(car) user=\(user)")
            }
        }
    }

    func testPresentation() {
        XCTAssertEqual(CarPresentationPolicy(carSupportsVideo: false).presentation(isAudioOnly: false), .audio,
                       "car without video support presents audio")
        XCTAssertEqual(CarPresentationPolicy(carSupportsVideo: true, userAllowsVideoInCar: false).presentation(isAudioOnly: false), .audio,
                       "user turned car video off")
        let allOn = CarPresentationPolicy(carSupportsVideo: true, userAllowsVideoInCar: true)
        XCTAssertEqual(allOn.presentation(isAudioOnly: false), .video)
        XCTAssertEqual(allOn.presentation(isAudioOnly: true), .audio, "audio-only items never present as video")
    }

    func testRowAction() {
        XCTAssertEqual(CarPresentationPolicy.rowAction(isCurrent: true, isActive: true), .pause)
        XCTAssertEqual(CarPresentationPolicy.rowAction(isCurrent: true, isActive: false), .play)
        XCTAssertEqual(CarPresentationPolicy.rowAction(isCurrent: false, isActive: true), .play)
        XCTAssertEqual(CarPresentationPolicy.rowAction(isCurrent: false, isActive: false), .play)
    }

    func testTapIntent() {
        XCTAssertEqual(CarPresentationPolicy.tapIntent(isCurrent: true, isActive: true, isPaused: false), .pause)
        XCTAssertEqual(CarPresentationPolicy.tapIntent(isCurrent: true, isActive: false, isPaused: true), .resume)
        XCTAssertEqual(CarPresentationPolicy.tapIntent(isCurrent: true, isActive: false, isPaused: false), .start,
                       "failed or idle current item restarts")
        XCTAssertEqual(CarPresentationPolicy.tapIntent(isCurrent: false, isActive: true, isPaused: false), .start)
        XCTAssertEqual(CarPresentationPolicy.tapIntent(isCurrent: false, isActive: false, isPaused: true), .start)
    }

    func testIsAudioOnly() {
        let resolver = PlaybackURLResolver()
        let hls = Sample.channel("Haber", url: "http://stream.example.com/live/haber.m3u8")
        XCTAssertEqual(resolver.isAudioOnly(hls, isXtreamSource: false), false)

        let radio = Sample.channel("Radyo", url: "http://radio.example.com/live/radyo.m3u8", isRadio: true)
        XCTAssertEqual(resolver.isAudioOnly(radio, isXtreamSource: false), true)

        let mp3 = Sample.channel("Mp3", url: "http://radio.example.com/stream.mp3")
        XCTAssertFalse(mp3.isRadio)
        XCTAssertEqual(resolver.isAudioOnly(mp3, isXtreamSource: false), true, "audio container counts as audio-only")

        let mkv = Sample.channel("Film", url: "http://vod.example.com/film.mkv", kind: .movie)
        XCTAssertNil(resolver.isAudioOnly(mkv, isXtreamSource: false))
        let rtsp = Sample.channel("Kamera", url: "rtsp://cam.example.com/stream")
        XCTAssertNil(resolver.isAudioOnly(rtsp, isXtreamSource: false))
    }
}
