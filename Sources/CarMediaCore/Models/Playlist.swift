import Foundation

/// The result of importing a channel list.
public struct Playlist: Sendable, Hashable, Codable {
    /// Channels in source order.
    public var channels: [Channel]
    /// Groups in order of first appearance. Channels without a group end up in a trailing
    /// group whose ``ChannelGroup/isUngrouped`` is `true`.
    public var groups: [ChannelGroup]
    /// Attributes from the `#EXTM3U` header line, keys lowercased.
    public var headerAttributes: [String: String]
    /// XMLTV guide URLs announced by the header (`url-tvg`, `x-tvg-url`, `tvg-url`).
    public var epgURLs: [URL]
    /// Number of entries dropped because their URL could not be understood.
    public var skippedEntryCount: Int

    /// Creates a playlist and derives ``groups`` from the channels.
    public init(
        channels: [Channel],
        headerAttributes: [String: String] = [:],
        epgURLs: [URL] = [],
        skippedEntryCount: Int = 0
    ) {
        self.channels = channels
        self.groups = Playlist.deriveGroups(from: channels)
        self.headerAttributes = headerAttributes
        self.epgURLs = epgURLs
        self.skippedEntryCount = skippedEntryCount
    }

    /// Builds a dictionary for O(1) lookups by channel id.
    public func makeIndex() -> [String: Channel] {
        Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Returns the channel with the given id (linear search; use ``makeIndex()`` for repeated lookups).
    public func channel(id: String) -> Channel? {
        channels.first { $0.id == id }
    }

    /// Returns the channels of a group in source order.
    public func channels(in group: ChannelGroup) -> [Channel] {
        let wanted = Set(group.channelIDs)
        return channels.filter { wanted.contains($0.id) }
    }

    static func deriveGroups(from channels: [Channel]) -> [ChannelGroup] {
        var order: [String] = []
        var members: [String: [String]] = [:]
        var ungrouped: [String] = []
        for channel in channels {
            guard let name = channel.groupTitle else {
                ungrouped.append(channel.id)
                continue
            }
            if members[name] == nil {
                order.append(name)
                members[name] = []
            }
            members[name]?.append(channel.id)
        }
        var groups = order.map { ChannelGroup(name: $0, channelIDs: members[$0] ?? []) }
        if !ungrouped.isEmpty {
            groups.append(ChannelGroup(name: nil, channelIDs: ungrouped))
        }
        return groups
    }
}
