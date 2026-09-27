import Foundation
import CarMediaCore

/// Movie or series.
public enum CatalogKind: String, Sendable, Hashable, Codable, CaseIterable {
    /// A single on-demand movie.
    case movie
    /// A series (seasons and episodes are loaded on demand).
    case series
}

/// One poster in the movie or series catalog of an Xtream account.
///
/// Holds Xtream ids, never stream URLs: those contain the password and are rebuilt when played.
public struct CatalogItem: Sendable, Hashable, Codable, Identifiable {
    /// Stable id (source + kind + Xtream id).
    public var id: String
    /// Movie or series.
    public var kind: CatalogKind
    /// Source (account) the item belongs to.
    public var sourceID: String
    /// Xtream `stream_id` (movies) or `series_id` (series).
    public var xtreamID: Int
    /// Display title.
    public var title: String
    /// Poster address as sent by the server.
    public var poster: String?
    /// Rating on a 0–10 scale, if known.
    public var rating: Double?
    /// Xtream category id.
    public var categoryID: String?
    /// When the item was added (movies) or last modified (series).
    public var added: Date?
    /// Container of the movie file (`mp4`, `mkv`…); `nil` for series.
    public var containerExtension: String?
    /// Release year, if the server provides one.
    public var year: String?

    /// Creates an item.
    public init(
        id: String,
        kind: CatalogKind,
        sourceID: String,
        xtreamID: Int,
        title: String,
        poster: String? = nil,
        rating: Double? = nil,
        categoryID: String? = nil,
        added: Date? = nil,
        containerExtension: String? = nil,
        year: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sourceID = sourceID
        self.xtreamID = xtreamID
        self.title = title
        self.poster = poster
        self.rating = rating
        self.categoryID = categoryID
        self.added = added
        self.containerExtension = containerExtension
        self.year = year
    }

    /// The stable id of a catalog item.
    public static func makeID(sourceID: String, kind: CatalogKind, xtreamID: Int) -> String {
        StableID.make("catalog", sourceID, kind.rawValue, String(xtreamID))
    }

    /// Poster as a URL, if valid.
    public var posterURL: URL? { poster.flatMap { PercentEncoding.lenientURL($0) } }

    /// Rating formatted with one decimal ("7.4"), or `nil` when unknown or zero.
    public var ratingText: String? {
        guard let rating, rating > 0 else { return nil }
        let tenths = Int((rating * 10).rounded())
        return "\(tenths / 10).\(tenths % 10)"
    }
}

/// A category with its item count.
public struct CatalogCategory: Sendable, Hashable, Identifiable {
    /// Xtream category id.
    public var id: String
    /// Display name.
    public var name: String
    /// Number of items in the category.
    public var count: Int
}

/// Sort orders offered in the catalog.
public enum CatalogSort: String, Sendable, Hashable, CaseIterable {
    /// Newest first.
    case recentlyAdded
    /// Alphabetical (Turkish-aware, case- and diacritic-insensitive).
    case name
    /// Highest rating first.
    case rating
}

/// The movie or series catalog of one Xtream account.
public struct VODCatalog: Sendable {
    /// All items in server order.
    public private(set) var items: [CatalogItem]
    /// Non-empty categories in server order.
    public private(set) var categories: [CatalogCategory]
    private var index: [String: Int]
    private var searchKeys: [String]
    private var sortKeys: [String]

    /// Creates a catalog. Categories without items are dropped; items of unknown categories stay searchable.
    public init(items: [CatalogItem], categories: [(id: String, name: String)]) {
        self.items = items
        var counts: [String: Int] = [:]
        for item in items {
            if let category = item.categoryID { counts[category, default: 0] += 1 }
        }
        var seen = Set<String>()
        self.categories = categories.compactMap { category in
            guard let count = counts[category.id], count > 0, seen.insert(category.id).inserted else { return nil }
            let name = category.name.trimmingCharacters(in: .whitespaces)
            return CatalogCategory(id: category.id, name: name.isEmpty ? category.id : name, count: count)
        }
        index = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        searchKeys = items.map { SearchNormalizer.normalize($0.title) }
        sortKeys = searchKeys
    }

    /// An empty catalog.
    public static let empty = VODCatalog(items: [], categories: [])

    /// `true` when there are no items.
    public var isEmpty: Bool { items.isEmpty }

    /// The item with `id`.
    public func item(id: String) -> CatalogItem? { index[id].map { items[$0] } }

    /// Items filtered by category and query, sorted.
    public func items(categoryID: String? = nil, query: String = "", sort: CatalogSort = .recentlyAdded) -> [CatalogItem] {
        let tokens = SearchNormalizer.tokens(query)
        var picked: [Int] = []
        picked.reserveCapacity(items.count)
        for (offset, item) in items.enumerated() {
            if let categoryID, item.categoryID != categoryID { continue }
            if !tokens.isEmpty, !SearchNormalizer.matches(normalizedKey: searchKeys[offset], tokens: tokens) { continue }
            picked.append(offset)
        }
        switch sort {
        case .recentlyAdded:
            picked.sort { lhs, rhs in
                let a = items[lhs].added ?? .distantPast
                let b = items[rhs].added ?? .distantPast
                return a != b ? a > b : lhs < rhs
            }
        case .name:
            picked.sort { lhs, rhs in
                sortKeys[lhs] != sortKeys[rhs] ? sortKeys[lhs] < sortKeys[rhs] : lhs < rhs
            }
        case .rating:
            picked.sort { lhs, rhs in
                let a = items[lhs].rating ?? -1
                let b = items[rhs].rating ?? -1
                return a != b ? a > b : lhs < rhs
            }
        }
        return picked.map { items[$0] }
    }

    // MARK: Building from Xtream responses

    /// Builds the movie catalog of `sourceID`.
    public static func movies(sourceID: String, streams: [XtreamVODStream], categories: [XtreamCategory]) -> VODCatalog {
        let items: [CatalogItem] = streams.compactMap { stream in
            guard let streamID = stream.streamID else { return nil }
            let title = clean(stream.name) ?? "#\(streamID)"
            return CatalogItem(
                id: CatalogItem.makeID(sourceID: sourceID, kind: .movie, xtreamID: streamID),
                kind: .movie,
                sourceID: sourceID,
                xtreamID: streamID,
                title: title,
                poster: clean(stream.streamIcon),
                rating: normalizedRating(tenBased: stream.rating, fiveBased: stream.rating5Based),
                categoryID: clean(stream.categoryID),
                added: unixDate(stream.added),
                containerExtension: clean(stream.containerExtension)
            )
        }
        return VODCatalog(items: items, categories: categoryPairs(categories))
    }

    /// Builds the series catalog of `sourceID`.
    public static func series(sourceID: String, list: [XtreamSeries], categories: [XtreamCategory]) -> VODCatalog {
        let items: [CatalogItem] = list.compactMap { series in
            guard let seriesID = series.seriesID else { return nil }
            let title = clean(series.name) ?? "#\(seriesID)"
            return CatalogItem(
                id: CatalogItem.makeID(sourceID: sourceID, kind: .series, xtreamID: seriesID),
                kind: .series,
                sourceID: sourceID,
                xtreamID: seriesID,
                title: title,
                poster: clean(series.cover),
                rating: normalizedRating(tenBased: series.rating, fiveBased: series.rating5Based),
                categoryID: clean(series.categoryID),
                added: unixDate(series.lastModified),
                year: year(fromReleaseDate: series.releaseDate)
            )
        }
        return VODCatalog(items: items, categories: categoryPairs(categories))
    }

    static func categoryPairs(_ categories: [XtreamCategory]) -> [(id: String, name: String)] {
        categories.compactMap { category in
            guard let id = clean(category.categoryID) else { return nil }
            return (id: id, name: category.categoryName ?? "")
        }
    }

    static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Prefers the 0–10 rating; falls back to the 5-based one doubled.
    static func normalizedRating(tenBased: Double?, fiveBased: Double?) -> Double? {
        if let tenBased, tenBased > 0, tenBased <= 10 { return tenBased }
        if let fiveBased, fiveBased > 0, fiveBased <= 5 { return fiveBased * 2 }
        return nil
    }

    /// Unix seconds as text → date.
    static func unixDate(_ text: String?) -> Date? {
        guard let text = clean(text), let seconds = Double(text), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// First four-digit year in a release date such as `2021-05-14`.
    public static func year(fromReleaseDate text: String?) -> String? {
        guard let text = clean(text) else { return nil }
        let digits = Array(text)
        var run = ""
        for character in digits {
            if character.isASCII, character.isNumber {
                run.append(character)
                if run.count == 4 { return run }
            } else {
                run = ""
            }
        }
        return nil
    }
}

// MARK: - Disk cache

/// A catalog as stored on disk: items and category names only (no stream URLs, no passwords).
public struct CatalogSnapshot: Sendable, Codable, Equatable {
    /// Bump when the format changes; older files are ignored.
    public static let currentVersion = 1

    /// A category id and name.
    public struct Category: Sendable, Codable, Equatable {
        public var id: String
        public var name: String
    }

    /// Format version.
    public var version: Int
    /// When the catalog was downloaded.
    public var savedAt: Date
    /// Items in server order.
    public var items: [CatalogItem]
    /// Categories in server order.
    public var categories: [Category]

    /// Creates a snapshot of `catalog`.
    public init(catalog: VODCatalog, savedAt: Date) {
        version = Self.currentVersion
        self.savedAt = savedAt
        items = catalog.items
        categories = catalog.categories.map { Category(id: $0.id, name: $0.name) }
    }

    /// The catalog, or `nil` if the snapshot was written by an incompatible version.
    public var catalog: VODCatalog? {
        guard version == Self.currentVersion else { return nil }
        return VODCatalog(items: items, categories: categories.map { (id: $0.id, name: $0.name) })
    }

    /// Whether the snapshot is older than `maxAge` at `date`.
    public func isStale(at date: Date, maxAge: TimeInterval) -> Bool {
        date.timeIntervalSince(savedAt) > maxAge || savedAt > date.addingTimeInterval(60)
    }
}
