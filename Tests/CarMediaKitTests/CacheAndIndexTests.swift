import Foundation
import XCTest
import CarMediaCore
@testable import CarMediaKit

final class AlphabetIndexTests: XCTestCase {
    private func channel(_ title: String, group: String = "Genel") -> Channel {
        Channel(id: title, title: title, streamURL: URL(string: "http://tv.example.com/\(abs(title.hashValue)).m3u8")!,
                groupTitle: group)
    }

    func testKeysFoldTurkishLettersAndSpecialCases() {
        XCTAssertEqual(AlphabetIndex.key(for: "Şimdi TV"), "S")
        XCTAssertEqual(AlphabetIndex.key(for: "İstanbul Haber"), "I")
        XCTAssertEqual(AlphabetIndex.key(for: "ıssız"), "I")
        XCTAssertEqual(AlphabetIndex.key(for: "Çocuk Kanalı"), "C")
        XCTAssertEqual(AlphabetIndex.key(for: "  öğle"), "O")
        XCTAssertEqual(AlphabetIndex.key(for: "24 Haber"), AlphabetIndex.digitsKey)
        XCTAssertEqual(AlphabetIndex.key(for: "\"Alıntı\" TV"), "A")
        XCTAssertEqual(AlphabetIndex.key(for: "★"), AlphabetIndex.otherKey)
        XCTAssertEqual(AlphabetIndex.key(for: ""), AlphabetIndex.otherKey)
    }

    func testBucketsAreOrderedAndSorted() {
        let buckets = AlphabetIndex.buckets([
            channel("Zeta"), channel("ağaç"), channel("Ahtapot"), channel("1 Numara"), channel("★ Yıldız"), channel("Çınar"),
        ])
        XCTAssertEqual(buckets.map(\.letter), ["A", "C", "Z", AlphabetIndex.digitsKey, AlphabetIndex.otherKey])
        XCTAssertEqual(buckets[0].channels.map(\.title), ["ağaç", "Ahtapot"])
    }

    func testVisibleChannelsSkipHiddenGroups() throws {
        var state = LibraryState()
        state.setContent([(id: "s1", name: "Liste", playlist: Playlist(channels: [
            channel("A1", group: "Haber"), channel("B1", group: "Yabancı"), channel("A2", group: "Haber"),
        ]))])
        let foreign = try XCTUnwrap(state.groups.first { $0.name == "Yabancı" })
        state.setGroup(foreign.id, hidden: true)
        XCTAssertEqual(state.visibleChannels.map(\.title), ["A1", "A2"])
    }
}

final class CatalogSnapshotTests: XCTestCase {
    private func catalog() -> VODCatalog {
        let items = [
            CatalogItem(id: "m1", kind: .movie, sourceID: "xt", xtreamID: 1, title: "Bir", poster: "http://img.example.com/1.jpg",
                        rating: 7, categoryID: "10", added: Date(timeIntervalSince1970: 100), containerExtension: "mp4"),
            CatalogItem(id: "m2", kind: .movie, sourceID: "xt", xtreamID: 2, title: "İki", categoryID: "11"),
        ]
        return VODCatalog(items: items, categories: [(id: "10", name: "Aksiyon"), (id: "11", name: "Dram")])
    }

    func testRoundTripKeepsItemsCategoriesAndCounts() throws {
        let snapshot = CatalogSnapshot(catalog: catalog(), savedAt: Date(timeIntervalSince1970: 1_000))
        let decoded = try JSONDecoder().decode(CatalogSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
        let restored = try XCTUnwrap(decoded.catalog)
        XCTAssertEqual(restored.items, catalog().items)
        XCTAssertEqual(restored.categories.map(\.name), ["Aksiyon", "Dram"])
        XCTAssertEqual(restored.categories.map(\.count), [1, 1])
        XCTAssertEqual(restored.items(query: "iki").map(\.xtreamID), [2])
    }

    func testIncompatibleVersionIsIgnored() {
        var snapshot = CatalogSnapshot(catalog: catalog(), savedAt: Date())
        snapshot.version = CatalogSnapshot.currentVersion + 1
        XCTAssertNil(snapshot.catalog)
    }

    func testStaleness() {
        let saved = Date(timeIntervalSince1970: 10_000)
        let snapshot = CatalogSnapshot(catalog: catalog(), savedAt: saved)
        XCTAssertFalse(snapshot.isStale(at: saved.addingTimeInterval(3600), maxAge: 6 * 3600))
        XCTAssertTrue(snapshot.isStale(at: saved.addingTimeInterval(7 * 3600), maxAge: 6 * 3600))
        XCTAssertTrue(snapshot.isStale(at: saved.addingTimeInterval(-3600), maxAge: 6 * 3600), "clock moved back")
    }
}

final class SampleContentTests: XCTestCase {
    private let json = """
    {"version":1,"collections":[
      {"id":"blender","title":"Açık filmler","subtitle":"Blender","items":[
        {"id":"blender-sintel","title":"Sintel","year":2010,"summary":"Kayıp ejderha","videoURL":"https://video.example.com/sintel-720.mp4",
         "posterURL":"https://img.example.com/sintel.jpg","duration":888,"license":"CC BY 3.0",
         "licenseURL":"https://creativecommons.org/licenses/by/3.0/","attribution":"© 2010 Blender Foundation | www.blender.org",
         "sourceURL":"https://durian.example.com"}]},
      {"id":"nasa","title":"Uzay ve NASA","subtitle":"NASA","items":[
        {"id":"nasa-apollo","title":"Apollo 11 fırlatılışı","year":1969,"summary":"Satürn V","videoURL":"https://nasa.example.com/a.mp4",
         "posterURL":null,"duration":null,"license":"Kamu malı","licenseURL":null,"attribution":"Video: NASA.","sourceURL":null}]}
    ]}
    """

    func testDecodesManifestAndBuildsSeekablePlayables() throws {
        let content = try SampleContent.decode(Data(json.utf8))
        XCTAssertEqual(content.collections.map(\.id), ["blender", "nasa"])
        XCTAssertEqual(content.allItems.count, 2)
        let sintel = try XCTUnwrap(content.item(id: "blender-sintel"))
        let channel = sintel.channel
        XCTAssertEqual(channel.kind, .movie)
        XCTAssertEqual(channel.duration, 888)
        XCTAssertEqual(channel.logoURL?.absoluteString, "https://img.example.com/sintel.jpg")
        guard case .playable(let request) = PlaybackURLResolver().resolve(channel, isXtreamSource: false) else {
            return XCTFail("sample must be playable")
        }
        XCTAssertFalse(request.isLive)
        XCTAssertEqual(content.search("apollo").map(\.id), ["nasa-apollo"])
        XCTAssertEqual(content.search("ejderha").map(\.id), ["blender-sintel"])
    }

    func testBundledManifestIsValid() throws {
        // The shipped manifest lives in the app target; validate it from the repository checkout.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/CarMedya/Resources/SampleContent.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("manifest not found") }
        let content = try SampleContent.decode(Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(content.allItems.count, 10)
        for item in content.allItems {
            XCTAssertTrue(["video.blender.org", "images-assets.nasa.gov"].contains(item.videoURL.host ?? ""), item.id)
            XCTAssertEqual(item.videoURL.scheme, "https", item.id)
            XCTAssertFalse(item.attribution.isEmpty, item.id)
            XCTAssertFalse(item.license.isEmpty, item.id)
            if case .unsupported = PlaybackURLResolver().resolve(item.channel, isXtreamSource: false) {
                XCTFail("unplayable sample \(item.id)")
            }
        }
        XCTAssertEqual(Set(content.allItems.map(\.id)).count, content.allItems.count, "ids must be unique")
    }
}
