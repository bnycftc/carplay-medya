import Foundation
import CarMediaCore

/// User choices that must survive relaunches: favorites and recently played channels.
///
/// Only channel ids are stored (never stream URLs, which may embed Xtream passwords).
public struct LibraryPreferences: Sendable, Hashable, Codable {
    /// Maximum number of recently played channels kept.
    public static let maxRecents = 20

    /// Favorite channel ids in the order the user added them.
    public var favoriteIDs: [String]
    /// Recently played channel ids, most recent first.
    public var recentIDs: [String]

    /// Creates preferences.
    public init(favoriteIDs: [String] = [], recentIDs: [String] = []) {
        self.favoriteIDs = favoriteIDs
        self.recentIDs = recentIDs
    }
}

/// A channel group of one source, as shown in the library.
public struct LibraryGroup: Sendable, Hashable, Identifiable {
    /// Unique across sources: `sourceID|groupID`.
    public var id: String
    /// Owning source.
    public var sourceID: String
    /// Group title, or `nil` for the "other" bucket (the UI shows a localized label).
    public var name: String?
    /// Member channel ids in source order.
    public var channelIDs: [String]

    /// Number of channels.
    public var count: Int { channelIDs.count }
}

/// All groups of one source.
public struct LibrarySection: Sendable, Hashable, Identifiable {
    /// Source id.
    public var id: String
    /// Source display name.
    public var title: String
    /// Groups in source order.
    public var groups: [LibraryGroup]
}

/// Pure, UI-independent library state: channels of every source, grouping, favorites, recents and search.
///
/// The phone UI and the CarPlay templates both render from this value.
public struct LibraryState: Sendable {
    /// Sources with their groups, in source order.
    public private(set) var sections: [LibrarySection] = []
    /// User preferences (favorites/recents).
    public private(set) var preferences: LibraryPreferences

    private var channelsByID: [String: Channel] = [:]
    private var orderedIDs: [String] = []
    private var sourceByChannel: [String: String] = [:]
    private var searchKeys: [String: String] = [:]

    /// Creates an empty library with the given preferences.
    public init(preferences: LibraryPreferences = LibraryPreferences()) {
        self.preferences = preferences
    }

    // MARK: Content

    /// Replaces all content. `sources` are `(id, name, playlist)` in display order.
    /// If two sources contain the same channel id, the first one wins.
    public mutating func setContent(_ sources: [(id: String, name: String, playlist: Playlist)]) {
        sections = []
        channelsByID = [:]
        orderedIDs = []
        sourceByChannel = [:]
        searchKeys = [:]
        for source in sources {
            // Register channels first; only ids first seen in this source belong to its groups.
            var owned = Set<String>()
            for channel in source.playlist.channels where channelsByID[channel.id] == nil {
                channelsByID[channel.id] = channel
                orderedIDs.append(channel.id)
                sourceByChannel[channel.id] = source.id
                searchKeys[channel.id] = SearchNormalizer.normalize(channel.title)
                owned.insert(channel.id)
            }
            var groups: [LibraryGroup] = []
            for group in source.playlist.groups {
                var seen = Set<String>()
                let memberIDs = group.channelIDs.filter { owned.contains($0) && seen.insert($0).inserted }
                guard !memberIDs.isEmpty else { continue }
                groups.append(LibraryGroup(
                    id: source.id + "|" + group.id,
                    sourceID: source.id,
                    name: group.name,
                    channelIDs: memberIDs
                ))
            }
            sections.append(LibrarySection(id: source.id, title: source.name, groups: groups))
        }
    }

    /// Replaces favorites/recents (e.g. after rebuilding content in the background).
    public mutating func setPreferences(_ preferences: LibraryPreferences) {
        self.preferences = preferences
    }

    /// All groups across sources.
    public var groups: [LibraryGroup] { sections.flatMap(\.groups) }

    /// Total number of distinct channels.
    public var channelCount: Int { orderedIDs.count }

    /// `true` when no source has any channel.
    public var isEmpty: Bool { orderedIDs.isEmpty }

    /// All channels in source order.
    public var allChannels: [Channel] { orderedIDs.compactMap { channelsByID[$0] } }

    /// Looks up a channel.
    public func channel(id: String) -> Channel? { channelsByID[id] }

    /// The source a channel belongs to.
    public func sourceID(forChannelID id: String) -> String? { sourceByChannel[id] }

    /// Channels of a group, in source order.
    public func channels(in group: LibraryGroup) -> [Channel] {
        group.channelIDs.compactMap { channelsByID[$0] }
    }

    /// Looks up a group by id.
    public func group(id: String) -> LibraryGroup? {
        groups.first { $0.id == id }
    }

    // MARK: Favorites

    /// Favorite channels that are currently available, in favorite order.
    public var favorites: [Channel] { preferences.favoriteIDs.compactMap { channelsByID[$0] } }

    /// Whether a channel is a favorite.
    public func isFavorite(_ id: String) -> Bool { preferences.favoriteIDs.contains(id) }

    /// Adds or removes a favorite. Returns the new state (`true` = now a favorite).
    @discardableResult
    public mutating func toggleFavorite(_ id: String) -> Bool {
        if let index = preferences.favoriteIDs.firstIndex(of: id) {
            preferences.favoriteIDs.remove(at: index)
            return false
        }
        preferences.favoriteIDs.append(id)
        return true
    }

    /// Reorders favorites (e.g. from a SwiftUI `onMove`). Indices refer to ``favorites``.
    public mutating func moveFavorite(from source: Int, to destination: Int) {
        let visible = favorites.map(\.id)
        guard visible.indices.contains(source), destination >= 0, destination <= visible.count else { return }
        var reordered = visible
        let moved = reordered.remove(at: source)
        reordered.insert(moved, at: destination > source ? destination - 1 : destination)
        // Keep favorites of currently unavailable sources at the end, in their original order.
        let hidden = preferences.favoriteIDs.filter { channelsByID[$0] == nil }
        preferences.favoriteIDs = reordered + hidden
    }

    // MARK: Recents

    /// Recently played channels that are currently available, most recent first.
    public var recents: [Channel] { preferences.recentIDs.compactMap { channelsByID[$0] } }

    /// Moves a channel to the front of the recents list (capped at ``LibraryPreferences/maxRecents``).
    public mutating func recordPlayed(_ id: String) {
        preferences.recentIDs.removeAll { $0 == id }
        preferences.recentIDs.insert(id, at: 0)
        if preferences.recentIDs.count > LibraryPreferences.maxRecents {
            preferences.recentIDs.removeLast(preferences.recentIDs.count - LibraryPreferences.maxRecents)
        }
    }

    /// Clears the recents list.
    public mutating func clearRecents() {
        preferences.recentIDs.removeAll()
    }

    /// Drops favorites/recents that belong to no current channel (e.g. after removing a source).
    public mutating func pruneUnavailablePreferences() {
        preferences.favoriteIDs.removeAll { channelsByID[$0] == nil }
        preferences.recentIDs.removeAll { channelsByID[$0] == nil }
    }

    // MARK: Search

    /// Channels whose title contains every word of `query` (case, diacritic and Turkish-i insensitive).
    /// An empty query returns no results.
    public func search(_ query: String, limit: Int = 200) -> [Channel] {
        let tokens = SearchNormalizer.tokens(query)
        guard !tokens.isEmpty, limit > 0 else { return [] }
        var results: [Channel] = []
        for id in orderedIDs {
            guard let key = searchKeys[id], SearchNormalizer.matches(normalizedKey: key, tokens: tokens) else { continue }
            if let channel = channelsByID[id] { results.append(channel) }
            if results.count >= limit { break }
        }
        return results
    }

    /// Filters `channels` by `query`; an empty query returns them unchanged.
    public func filter(_ channels: [Channel], query: String) -> [Channel] {
        let tokens = SearchNormalizer.tokens(query)
        guard !tokens.isEmpty else { return channels }
        return channels.filter { channel in
            let key = searchKeys[channel.id] ?? SearchNormalizer.normalize(channel.title)
            return SearchNormalizer.matches(normalizedKey: key, tokens: tokens)
        }
    }
}
