import Foundation
import XCTest
import CarMediaCore
@testable import CarMediaKit

final class VODCatalogTests: XCTestCase {
    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func movies() throws -> VODCatalog {
        let streams: [XtreamVODStream] = try decode("""
        [
          {"stream_id": "1", "name": " Zeta Film ", "stream_icon": "http://img.example.com/z.jpg", "rating": "6.1",
           "added": "1700000300", "category_id": "10", "container_extension": "mp4"},
          {"stream_id": 2, "name": "Ağaç Ev", "rating": "", "rating_5based": 4.5, "added": "1700000100",
           "category_id": "10", "container_extension": "mkv"},
          {"stream_id": 3, "name": "İstanbul Gecesi", "rating": "8", "added": "1700000200", "category_id": "11"},
          {"name": "Kimliksiz"},
          {"stream_id": 4, "name": "", "category_id": "99"}
        ]
        """)
        let categories: [XtreamCategory] = try decode("""
        [{"category_id": "10", "category_name": "Aksiyon"}, {"category_id": "11", "category_name": "Dram"},
         {"category_id": "12", "category_name": "Boş"}]
        """)
        return VODCatalog.movies(sourceID: "xt-1", streams: streams, categories: categories)
    }

    func testBuildsMoviesAndDropsItemsWithoutID() throws {
        let catalog = try movies()
        XCTAssertEqual(catalog.items.count, 4)
        let first = try XCTUnwrap(catalog.items.first)
        XCTAssertEqual(first.title, "Zeta Film")
        XCTAssertEqual(first.kind, .movie)
        XCTAssertEqual(first.xtreamID, 1)
        XCTAssertEqual(first.containerExtension, "mp4")
        XCTAssertEqual(first.posterURL?.absoluteString, "http://img.example.com/z.jpg")
        XCTAssertEqual(catalog.items[3].title, "#4")
        XCTAssertEqual(first.id, CatalogItem.makeID(sourceID: "xt-1", kind: .movie, xtreamID: 1))
        XCTAssertEqual(catalog.item(id: first.id)?.title, "Zeta Film")
    }

    func testCategoriesAreCountedAndEmptyOnesDropped() throws {
        let catalog = try movies()
        XCTAssertEqual(catalog.categories.map(\.name), ["Aksiyon", "Dram"])
        XCTAssertEqual(catalog.categories.map(\.count), [2, 1])
    }

    func testRatingsAreNormalizedToTenPointScale() throws {
        let catalog = try movies()
        XCTAssertEqual(catalog.items[0].rating, 6.1)
        XCTAssertEqual(catalog.items[1].rating, 9.0)
        XCTAssertEqual(catalog.items[1].ratingText, "9.0")
        XCTAssertNil(catalog.items[3].rating)
        XCTAssertNil(catalog.items[3].ratingText)
    }

    func testFilterSearchAndSort() throws {
        let catalog = try movies()
        XCTAssertEqual(catalog.items(sort: .recentlyAdded).map(\.xtreamID), [1, 3, 2, 4])
        XCTAssertEqual(catalog.items(sort: .name).map(\.title), ["#4", "Ağaç Ev", "İstanbul Gecesi", "Zeta Film"])
        XCTAssertEqual(catalog.items(sort: .rating).map(\.xtreamID), [2, 3, 1, 4])
        XCTAssertEqual(catalog.items(categoryID: "10", sort: .name).map(\.xtreamID), [2, 1])
        XCTAssertEqual(catalog.items(query: "istanbul").map(\.xtreamID), [3])
        XCTAssertEqual(catalog.items(query: "agac").map(\.xtreamID), [2])
        XCTAssertTrue(catalog.items(categoryID: "11", query: "zeta").isEmpty)
    }

    func testBuildsSeriesWithYearAndLastModified() throws {
        let list: [XtreamSeries] = try decode("""
        [{"series_id": 55, "name": "Örnek Dizi", "cover": "http://img.example.com/d.jpg", "rating": "7",
          "releaseDate": "2021-05-14", "last_modified": "1700000000", "category_id": "20"},
         {"series_id": 56, "name": "Yıl Yok", "releaseDate": "bilinmiyor"}]
        """)
        let catalog = VODCatalog.series(sourceID: "xt-1", list: list, categories: [])
        XCTAssertEqual(catalog.items.map(\.kind), [.series, .series])
        XCTAssertEqual(catalog.items[0].year, "2021")
        XCTAssertNil(catalog.items[1].year)
        XCTAssertEqual(catalog.items[0].added, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(catalog.categories.isEmpty)
        XCTAssertFalse(catalog.isEmpty)
        XCTAssertTrue(VODCatalog.empty.isEmpty)
    }
}

final class ContinueWatchingTests: XCTestCase {
    private func movie(_ id: Int) -> WatchTarget {
        WatchTarget(sourceID: "xt-1", kind: .movie, xtreamID: id, containerExtension: "mp4", title: "Film \(id)")
    }

    func testIgnoresEarlyPositionsAndInvalidInput() {
        var list = ContinueWatching()
        XCTAssertFalse(list.record(movie(1), position: 30, duration: 5400))
        XCTAssertFalse(list.record(movie(1), position: .nan, duration: 5400))
        XCTAssertFalse(list.record(movie(1), position: 600, duration: 0))
        XCTAssertTrue(list.entries.isEmpty)
    }

    func testRecordsAndResumesWithRewind() throws {
        var list = ContinueWatching()
        let target = movie(1)
        XCTAssertTrue(list.record(target, position: 600, duration: 5400, at: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(list.resumePosition(for: target.playableID), 595)
        let progress = try XCTUnwrap(list.progress(for: target.playableID))
        XCTAssertEqual(progress.fraction, 600.0 / 5400.0, accuracy: 0.0001)
        XCTAssertEqual(progress.minutesRemaining, 80)
        // An early tick after resuming must not erase the saved position.
        XCTAssertFalse(list.record(target, position: 2, duration: 5400))
        XCTAssertEqual(list.resumePosition(for: target.playableID), 595)
    }

    func testMostRecentFirstAndCapacity() {
        var list = ContinueWatching()
        for id in 1...(ContinueWatching.capacity + 5) {
            list.record(movie(id), position: 120, duration: 3600, at: Date(timeIntervalSince1970: Double(id)))
        }
        XCTAssertEqual(list.entries.count, ContinueWatching.capacity)
        XCTAssertEqual(list.entries.first?.target.xtreamID, ContinueWatching.capacity + 5)
        list.record(movie(10), position: 200, duration: 3600)
        XCTAssertEqual(list.entries.first?.target.xtreamID, 10)
        XCTAssertEqual(list.entries.filter { $0.target.xtreamID == 10 }.count, 1)
    }

    func testFinishingMarksWatchedAndRewatchClearsMark() {
        var list = ContinueWatching()
        let target = movie(7)
        list.record(target, position: 900, duration: 1000)
        XCTAssertTrue(list.record(target, position: 960, duration: 1000))
        XCTAssertNil(list.progress(for: target.playableID))
        XCTAssertTrue(list.isWatched(target.playableID))
        XCTAssertFalse(list.record(target, position: 990, duration: 1000))
        list.record(target, position: 300, duration: 1000)
        XCTAssertFalse(list.isWatched(target.playableID))
        XCTAssertNotNil(list.progress(for: target.playableID))
    }

    func testEpisodeIDsAreDistinctAndSourceRemovalWorks() {
        var list = ContinueWatching()
        let e1 = WatchTarget(sourceID: "xt-1", kind: .series, xtreamID: 55, episodeID: "900", title: "Dizi")
        let e2 = WatchTarget(sourceID: "xt-1", kind: .series, xtreamID: 55, episodeID: "901", title: "Dizi")
        let other = WatchTarget(sourceID: "xt-2", kind: .movie, xtreamID: 1, title: "Başka")
        XCTAssertNotEqual(e1.playableID, e2.playableID)
        list.record(e1, position: 100, duration: 2000)
        list.record(e2, position: 100, duration: 2000)
        list.record(other, position: 100, duration: 2000)
        list.removeAll(sourceID: "xt-1")
        XCTAssertEqual(list.entries.map(\.target.sourceID), ["xt-2"])
        list.clear()
        XCTAssertTrue(list.entries.isEmpty)
    }

    func testCodableRoundTripHasNoURLs() throws {
        var list = ContinueWatching()
        list.record(movie(1), position: 120, duration: 3600, at: Date(timeIntervalSince1970: 10))
        let data = try JSONEncoder().encode(list)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("/movie/"))
        XCTAssertEqual(try JSONDecoder().decode(ContinueWatching.self, from: data), list)
    }
}

final class GuidePresenterTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    // 2026-09-26 12:00 UTC
    private let now = Date(timeIntervalSince1970: 1_790_424_000)

    private func store() -> EPGStore {
        func programme(_ offsetMinutes: Double, _ length: Double, _ title: String) -> Programme {
            let start = now.addingTimeInterval(offsetMinutes * 60)
            return Programme(channelID: "kanal.1", start: start, stop: start.addingTimeInterval(length * 60), title: title)
        }
        return EPGStore(
            channels: [EPGChannel(id: "kanal.1", displayNames: ["Kanal Bir"])],
            programmes: [
                programme(-24 * 60 - 10, 60, "Dün"),
                programme(-120, 60, "Sabah"),
                programme(-30, 60, "Öğle"),
                programme(30, 60, "Akşam"),
                programme(3 * 24 * 60, 60, "Çok ileri"),
            ]
        )
    }

    private func channel(catchup: String?) -> Channel {
        Channel(id: "c1", title: "Kanal Bir", streamURL: URL(string: "http://tv.example.com/live/u/p/1.m3u8")!,
                tvgID: "kanal.1", catchup: catchup, attributes: ["catchup-days": "1"])
    }

    func testGroupsByDayAndMarksStates() throws {
        let presenter = GuidePresenter(timeZone: utc)
        let days = presenter.schedule(for: channel(catchup: nil), in: store(), now: now)
        XCTAssertEqual(days.map(\.dayOffset), [-1, 0])
        let today = try XCTUnwrap(days.last)
        XCTAssertEqual(today.entries.map(\.programme.title), ["Sabah", "Öğle", "Akşam"])
        XCTAssertEqual(today.entries.map(\.state), [.past, .live, .upcoming])
        XCTAssertEqual(today.entries[1].progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(today.entries[0].timeRange, "10:00\u{2013}11:00")
        XCTAssertEqual(GuidePresenter.liveEntry(in: days)?.programme.title, "Öğle")
        XCTAssertFalse(today.entries.contains { $0.canReplay })
    }

    func testReplayAvailabilityFollowsArchiveDepth() throws {
        let presenter = GuidePresenter(timeZone: utc)
        let days = presenter.schedule(for: channel(catchup: "xc"), in: store(), now: now)
        let all = days.flatMap(\.entries)
        XCTAssertEqual(all.filter(\.canReplay).map(\.programme.title), ["Sabah"])
    }

    func testUnknownChannelHasNoGuide() {
        let presenter = GuidePresenter(timeZone: utc)
        let unknown = Channel(id: "x", title: "Yok", streamURL: URL(string: "http://tv.example.com/x.m3u8")!, tvgID: "yok")
        XCTAssertTrue(presenter.schedule(for: unknown, in: store(), now: now).isEmpty)
        XCTAssertFalse(presenter.hasGuide(unknown, in: store()))
        XCTAssertTrue(presenter.hasGuide(channel(catchup: nil), in: store()))
    }
}
