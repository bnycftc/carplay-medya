import Foundation
import XCTest
import CarMediaCore
@testable import CarMediaKit

final class MotionPolicyTests: XCTestCase {
    private func kmh(_ value: Double) -> Double { value / 3.6 }

    func testHysteresisBetweenThresholds() {
        var policy = MotionPolicy()
        XCTAssertTrue(policy.allowsVideo)
        XCTAssertTrue(policy.update(speed: kmh(7.9)), "below 8 km/h stays stopped")
        XCTAssertFalse(policy.update(speed: kmh(8)), "8 km/h starts moving")
        XCTAssertFalse(policy.update(speed: kmh(5)), "between thresholds keeps moving")
        XCTAssertFalse(policy.update(speed: kmh(3.1)))
        XCTAssertTrue(policy.update(speed: kmh(3)), "3 km/h counts as stopped")
        XCTAssertTrue(policy.update(speed: kmh(5)), "between thresholds keeps stopped")
    }

    func testInvalidReadingsKeepState() {
        var policy = MotionPolicy()
        policy.update(speed: kmh(50))
        XCTAssertFalse(policy.update(speed: -1), "CLLocation reports -1 when unknown")
        XCTAssertFalse(policy.update(speed: .nan))
        XCTAssertTrue(policy.isMoving)
    }

    func testCarPlayWithoutSpeedStillAllowsVideo() {
        var policy = MotionPolicy()
        XCTAssertTrue(policy.update(carPlayConnected: true), "unknown speed (parked, no GPS fix) must not hide video")
        XCTAssertTrue(policy.update(speed: -1))
        XCTAssertTrue(policy.update(speed: 0), "a valid standstill reading allows video")
        XCTAssertFalse(policy.update(speed: kmh(20)))
        XCTAssertTrue(policy.update(carPlayConnected: false), "disconnect resets the state")
        XCTAssertFalse(policy.hasSpeedReading)
    }

    func testDisabledPolicyAlwaysAllowsVideoAndCustomThresholds() {
        var disabled = MotionPolicy(isEnabled: false)
        disabled.update(carPlayConnected: true)
        XCTAssertTrue(disabled.update(speed: kmh(100)))

        let custom = MotionPolicy(movingKmh: 10, stoppedKmh: 20)
        XCTAssertEqual(custom.movingThreshold, kmh(10), accuracy: 0.0001)
        XCTAssertEqual(custom.stoppedThreshold, custom.movingThreshold, "stopped threshold is clamped")
    }
}

final class PlaybackURLResolverTests: XCTestCase {
    private let resolver = PlaybackURLResolver()

    private func request(_ resolution: PlaybackResolution, file: StaticString = #filePath, line: UInt = #line) -> PlaybackRequest? {
        guard case .playable(let request) = resolution else {
            XCTFail("expected playable, got \(resolution)", file: file, line: line)
            return nil
        }
        return request
    }

    func testHLSIsPlayableAndLive() {
        let channel = Sample.channel("Haber", url: "http://stream.example.com/live/haber.m3u8")
        let result = request(resolver.resolve(channel, isXtreamSource: false))
        XCTAssertEqual(result?.url, channel.streamURL)
        XCTAssertEqual(result?.isLive, true)
        XCTAssertEqual(result?.isAudioOnly, false)
    }

    func testXtreamTransportStreamIsRewrittenToHLSKeepingEncodedCredentials() {
        let channel = Sample.channel("X", url: "http://panel.example.com:8080/live/demo/p%40ss/42.ts")
        let result = request(resolver.resolve(channel, isXtreamSource: true))
        XCTAssertEqual(result?.url.absoluteString, "http://panel.example.com:8080/live/demo/p%40ss/42.m3u8")
    }

    func testPlainM3UTransportStreamIsUnsupportedUnlessRewriteEnabled() {
        let channel = Sample.channel("T", url: "http://panel.example.com/live/demo/pass/42.ts")
        XCTAssertEqual(resolver.resolve(channel, isXtreamSource: false), .unsupported(.rawTransportStream))
        let lenient = PlaybackURLResolver(rewriteXtreamStylePathsInM3U: true)
        XCTAssertEqual(request(lenient.resolve(channel, isXtreamSource: false))?.url.pathExtension, "m3u8")
        let other = Sample.channel("O", url: "http://cdn.example.com/stream.ts")
        XCTAssertEqual(lenient.resolve(other, isXtreamSource: false), .unsupported(.rawTransportStream))
    }

    func testUnsupportedContainersAndProtocols() {
        XCTAssertEqual(resolver.resolve(Sample.channel("M", url: "http://vod.example.com/movie/a/b/1.mkv", kind: .movie), isXtreamSource: true),
                       .unsupported(.matroska))
        XCTAssertEqual(resolver.resolve(Sample.channel("R", url: "rtsp://cam.example.com/stream"), isXtreamSource: false),
                       .unsupported(.rtsp))
        XCTAssertEqual(resolver.resolve(Sample.channel("U", url: "udp://239.0.0.1:1234"), isXtreamSource: false),
                       .unsupported(.udp))
        XCTAssertEqual(resolver.resolve(Sample.channel("A", url: "http://vod.example.com/a.avi", kind: .movie), isXtreamSource: false),
                       .unsupported(.container))
        XCTAssertEqual(resolver.resolve(Sample.channel("S", url: "srt://live.example.com:9000"), isXtreamSource: false),
                       .unsupported(.otherProtocol))
    }

    func testAudioMovieAndHeaders() {
        var radio = Sample.channel("Radyo", url: "http://radio.example.com/stream.mp3")
        radio.userAgent = "Deneme/1.0"
        radio.referrer = "http://example.com/"
        let result = request(resolver.resolve(radio, isXtreamSource: false))
        XCTAssertEqual(result?.isAudioOnly, true)
        XCTAssertEqual(result?.userAgent, "Deneme/1.0")
        XCTAssertEqual(result?.referrer, "http://example.com/")

        let movie = Sample.channel("Film", url: "http://vod.example.com/film.mp4", kind: .movie)
        XCTAssertEqual(request(resolver.resolve(movie, isXtreamSource: false))?.isLive, false)
    }
}

final class NowPlayingStateTests: XCTestCase {
    private let a = Sample.channel("A", group: "G")
    private let b = Sample.channel("B")
    private let c = Sample.channel("C")

    private func liveRequest(_ channel: Channel) -> PlaybackRequest {
        PlaybackRequest(url: channel.streamURL, userAgent: nil, referrer: nil, isLive: true, isAudioOnly: false)
    }

    func testLifecycle() {
        var state = NowPlayingState()
        XCTAssertFalse(state.isActive)
        state.markPlaying()
        XCTAssertEqual(state.phase, .idle, "no channel, no transition")

        state.begin(a, request: liveRequest(a), queue: [a, b])
        XCTAssertEqual(state.phase, .loading)
        XCTAssertEqual(state.subtitle, "G")
        state.markPlaying()
        XCTAssertTrue(state.isPlaying)
        state.markPaused()
        XCTAssertEqual(state.phase, .paused)
        state.programmeTitle = "Akşam Haberleri"
        XCTAssertEqual(state.subtitle, "Akşam Haberleri")
        state.stop()
        XCTAssertEqual(state, NowPlayingState())
    }

    func testFailureIsRedactedAndSticky() {
        var state = NowPlayingState()
        state.begin(a, request: liveRequest(a))
        struct Leaky: Error, CustomStringConvertible {
            var description: String { "failed http://panel.example.com/live/demo/s3cret/1.m3u8" }
        }
        state.fail(Leaky(), secrets: ["s3cret"])
        guard case .failed(let kind, let detail) = state.phase else { return XCTFail("expected failure") }
        XCTAssertEqual(kind, .unknown)
        XCTAssertFalse(detail?.contains("s3cret") ?? true)
        XCTAssertTrue(detail?.contains(Redaction.placeholder) ?? false)
        state.markPaused()
        state.markBuffering()
        XCTAssertTrue(state.isFailed, "late player callbacks must not hide the error")
    }

    func testLiveHasNoProgressButOnDemandDoes() {
        var state = NowPlayingState()
        state.begin(a, request: liveRequest(a))
        state.updateTime(elapsed: 30, duration: 60)
        XCTAssertNil(state.progress)
        XCTAssertFalse(state.canSeek)

        let movie = Sample.channel("Film", url: "http://vod.example.com/film.mp4", kind: .movie)
        state.begin(movie, request: PlaybackRequest(url: movie.streamURL, userAgent: nil, referrer: nil, isLive: false, isAudioOnly: false))
        state.updateTime(elapsed: 30, duration: 120)
        XCTAssertEqual(state.progress ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertTrue(state.canSeek)
        state.updateTime(elapsed: .nan, duration: .infinity)
        XCTAssertEqual(state.elapsed, 30)
        XCTAssertNil(state.duration)
    }

    func testRejectKeepsChannelAndReason() {
        var state = NowPlayingState()
        state.begin(a, request: liveRequest(a))
        state.markPlaying()
        let movie = Sample.channel("Film", url: "http://vod.example.com/film.mkv", kind: .movie)
        state.reject(movie, reason: .matroska, queue: [a, movie])
        XCTAssertEqual(state.channel?.id, movie.id)
        XCTAssertEqual(state.failure, .unsupported(.matroska))
        XCTAssertFalse(state.isLive)
        XCTAssertEqual(state.nextChannel?.id, a.id, "zapping past an unsupported item still works")
    }

    func testNextAndPreviousWrapAround() {
        var state = NowPlayingState()
        state.begin(c, request: liveRequest(c), queue: [a, b, c])
        XCTAssertEqual(state.nextChannel?.id, a.id)
        XCTAssertEqual(state.previousChannel?.id, b.id)
        state.begin(a, request: liveRequest(a), queue: [b, c])
        XCTAssertNil(state.nextChannel, "a queue that does not contain the channel is replaced by the channel alone")
    }

    func testNextWithoutWrapStopsAtTheEnd() {
        var state = NowPlayingState()
        state.begin(a, request: liveRequest(a), queue: [a, b, c])
        XCTAssertEqual(state.nextChannelWithoutWrap?.id, b.id)
        state.begin(c, request: liveRequest(c), queue: [a, b, c])
        XCTAssertNil(state.nextChannelWithoutWrap, "the last item has no next one")
        state.begin(a, request: liveRequest(a), queue: [a])
        XCTAssertNil(state.nextChannelWithoutWrap)
    }
}
