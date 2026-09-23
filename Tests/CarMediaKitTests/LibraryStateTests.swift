import Foundation
import XCTest
import CarMediaCore
@testable import CarMediaKit

final class LibraryStateTests: XCTestCase {
    private let haber = Sample.channel("Haber Bir", group: "Haber")
    private let spor = Sample.channel("Spor Deneme", group: "Spor")
    private let ilce = Sample.channel("İLÇE Kanalı", group: "Haber")
    private let radyo = Sample.channel("Radyo Işık", isRadio: true)

    private func makeLibrary() -> LibraryState {
        var library = LibraryState()
        library.setContent([
            (id: "s1", name: "Ev", playlist: Playlist(channels: [haber, spor, ilce])),
            (id: "s2", name: "Hesap", playlist: Playlist(channels: [radyo, haber])),
        ])
        return library
    }

    func testGroupsAreScopedPerSourceAndDuplicatesGoToFirstSource() {
        let library = makeLibrary()
        XCTAssertEqual(library.sections.map(\.title), ["Ev", "Hesap"])
        XCTAssertEqual(library.sections[0].groups.map(\.name), ["Haber", "Spor"])
        XCTAssertEqual(library.sections[0].groups[0].channelIDs, [haber.id, ilce.id])
        // `haber` also appears in s2 but belongs to s1; s2 only keeps its own ungrouped radio.
        XCTAssertEqual(library.sections[1].groups.count, 1)
        XCTAssertNil(library.sections[1].groups[0].name)
        XCTAssertEqual(library.sections[1].groups[0].channelIDs, [radyo.id])
        XCTAssertEqual(library.channelCount, 4)
        XCTAssertEqual(library.sourceID(forChannelID: haber.id), "s1")
        XCTAssertEqual(library.sourceID(forChannelID: radyo.id), "s2")
    }

    func testFavoritesToggleAndSkipUnavailableChannels() {
        var library = LibraryState(preferences: LibraryPreferences(favoriteIDs: ["gone"]))
        library.setContent([(id: "s1", name: "Ev", playlist: Playlist(channels: [haber, spor]))])
        XCTAssertTrue(library.toggleFavorite(spor.id))
        XCTAssertTrue(library.toggleFavorite(haber.id))
        XCTAssertEqual(library.favorites.map(\.id), [spor.id, haber.id])
        XCTAssertFalse(library.toggleFavorite(spor.id))
        XCTAssertEqual(library.favorites.map(\.id), [haber.id])
        XCTAssertTrue(library.preferences.favoriteIDs.contains("gone"), "favorites of offline sources are kept")
    }

    func testMoveFavoriteKeepsHiddenOnesAtTheEnd() {
        var library = LibraryState(preferences: LibraryPreferences(favoriteIDs: [haber.id, "gone", spor.id, ilce.id]))
        library.setContent([(id: "s1", name: "Ev", playlist: Playlist(channels: [haber, spor, ilce]))])
        library.moveFavorite(from: 2, to: 0)
        XCTAssertEqual(library.favorites.map(\.id), [ilce.id, haber.id, spor.id])
        XCTAssertEqual(library.preferences.favoriteIDs.last, "gone")
    }

    func testSetPreferencesReplacesFavoritesAndRecents() {
        var library = makeLibrary()
        library.setPreferences(LibraryPreferences(favoriteIDs: [spor.id], recentIDs: [radyo.id]))
        XCTAssertEqual(library.favorites.map(\.id), [spor.id])
        XCTAssertEqual(library.recents.map(\.id), [radyo.id])
    }

    func testRecentsAreMostRecentFirstDedupedAndCapped() {
        var library = makeLibrary()
        library.recordPlayed(haber.id)
        library.recordPlayed(spor.id)
        library.recordPlayed(haber.id)
        XCTAssertEqual(library.recents.map(\.id), [haber.id, spor.id])
        for index in 0..<30 { library.recordPlayed("x\(index)") }
        XCTAssertEqual(library.preferences.recentIDs.count, LibraryPreferences.maxRecents)
        XCTAssertEqual(library.preferences.recentIDs.first, "x29")
    }

    func testSearchIsCaseDiacriticAndTurkishIInsensitive() {
        let library = makeLibrary()
        XCTAssertEqual(library.search("ilce").map(\.id), [ilce.id])
        XCTAssertEqual(library.search("İlçe KANAL").map(\.id), [ilce.id])
        XCTAssertEqual(library.search("isik").map(\.id), [radyo.id])
        XCTAssertEqual(library.search("RADYO ışık").map(\.id), [radyo.id])
        XCTAssertTrue(library.search("   ").isEmpty)
        XCTAssertEqual(library.search("a", limit: 2).count, 2)
    }

    func testFilterWithinGroupAndPrune() {
        var library = LibraryState(preferences: LibraryPreferences(favoriteIDs: ["gone", spor.id], recentIDs: ["gone"]))
        library.setContent([(id: "s1", name: "Ev", playlist: Playlist(channels: [haber, spor, ilce]))])
        let group = library.sections[0].groups[0]
        XCTAssertEqual(library.filter(library.channels(in: group), query: "bir").map(\.id), [haber.id])
        XCTAssertEqual(library.filter(library.channels(in: group), query: "").count, 2)
        library.pruneUnavailablePreferences()
        XCTAssertEqual(library.preferences.favoriteIDs, [spor.id])
        XCTAssertTrue(library.preferences.recentIDs.isEmpty)
    }
}
