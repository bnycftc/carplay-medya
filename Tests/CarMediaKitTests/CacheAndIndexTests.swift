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
