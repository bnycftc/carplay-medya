import Foundation

/// A named group of channels, in order of first appearance in the source.
public struct ChannelGroup: Sendable, Hashable, Codable, Identifiable {
    /// Stable id derived from the group name.
    public var id: String
    /// Group title as written in the source, or `nil` for channels without a group.
    /// The UI should show a localized label (e.g. "Diğer") for the ungrouped bucket.
    public var name: String?
    /// Member channel ids in source order.
    public var channelIDs: [String]

    /// Creates a group.
    public init(name: String?, channelIDs: [String] = []) {
        self.id = ChannelGroup.id(for: name)
        self.name = name
        self.channelIDs = channelIDs
    }

    /// `true` for the bucket holding channels without a group title.
    public var isUngrouped: Bool { name == nil }

    /// The stable id for a group name.
    public static func id(for name: String?) -> String {
        guard let name else { return "ungrouped" }
        return "g-" + StableID.make(name)
    }
}
