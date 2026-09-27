import Foundation
import CarMediaCore

/// Free sample videos that ship with the app so a first launch is never empty.
///
/// Only openly licensed material whose rights can be documented is allowed here (CLAUDE.md red line):
/// Blender open movies (Creative Commons BY / BY-SA, played from the Blender Foundation's own server)
/// and NASA videos (U.S. government works, from NASA's own archive). No TV channels, no third-party lists.
public struct SampleContent: Sendable, Codable, Equatable {
    /// Format version of the bundled manifest.
    public var version: Int
    /// Collections in display order.
    public var collections: [SampleCollection]

    /// Creates a manifest.
    public init(version: Int, collections: [SampleCollection]) {
        self.version = version
        self.collections = collections
    }

    /// Decodes the bundled manifest.
    public static func decode(_ data: Data) throws -> SampleContent {
        try JSONDecoder().decode(SampleContent.self, from: data)
    }

    /// All items in display order.
    public var allItems: [SampleItem] { collections.flatMap(\.items) }

    /// The item with `id`.
    public func item(id: String) -> SampleItem? { allItems.first { $0.id == id } }

    /// Items whose title or summary matches `query` (Turkish-aware, like channel search).
    public func search(_ query: String) -> [SampleItem] {
        let tokens = SearchNormalizer.tokens(query)
        guard !tokens.isEmpty else { return [] }
        return allItems.filter { item in
            SearchNormalizer.matches(normalizedKey: SearchNormalizer.normalize(item.title + " " + item.summary), tokens: tokens)
        }
    }
}

/// A themed group of samples ("Açık filmler", "Uzay ve NASA").
public struct SampleCollection: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var items: [SampleItem]
}

/// One sample video with the license text shown next to it.
public struct SampleItem: Sendable, Codable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var year: Int
    public var summary: String
    public var videoURL: URL
    public var posterURL: URL?
    /// Seconds, when known in advance.
    public var duration: Double?
    /// License name, e.g. "CC BY 3.0" or "Kamu malı".
    public var license: String
    public var licenseURL: URL?
    /// Required credit line.
    public var attribution: String
    /// The rights holder's page for the work.
    public var sourceURL: URL?

    /// The playable. Samples are on-demand files, so they are seekable and never "live".
    public var channel: Channel {
        Channel(
            id: StableID.make("sample", id),
            title: title,
            streamURL: videoURL,
            kind: .movie,
            groupTitle: attribution,
            logo: posterURL?.absoluteString,
            duration: duration
        )
    }
}
