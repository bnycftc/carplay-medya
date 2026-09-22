import Foundation

/// A channel declared in an XMLTV guide (`<channel id="…">`).
public struct EPGChannel: Sendable, Hashable, Codable, Identifiable {
    /// XMLTV channel id; matched against M3U `tvg-id`.
    public var id: String
    /// All `<display-name>` values in document order.
    public var displayNames: [String]
    /// `<icon src="…">`.
    public var iconURL: URL?

    /// Creates an EPG channel.
    public init(id: String, displayNames: [String] = [], iconURL: URL? = nil) {
        self.id = id
        self.displayNames = displayNames
        self.iconURL = iconURL
    }

    /// The first display name, if any.
    public var displayName: String? { displayNames.first }
}

/// A single programme guide entry.
public struct Programme: Sendable, Hashable, Codable, Identifiable {
    /// XMLTV channel id this programme airs on.
    public var channelID: String
    /// Start time.
    public var start: Date
    /// End time. When the source omits it, ``EPGStore`` fills it from the next programme's start.
    public var stop: Date
    /// Title.
    public var title: String
    /// `<sub-title>`.
    public var subtitle: String?
    /// `<desc>`.
    public var description: String?
    /// `<category>` values.
    public var categories: [String]
    /// `<episode-num>` (the `onscreen` system is preferred when several are present).
    public var episodeNumber: String?
    /// `<icon src="…">`.
    public var iconURL: URL?

    /// Creates a programme.
    public init(
        channelID: String,
        start: Date,
        stop: Date,
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        categories: [String] = [],
        episodeNumber: String? = nil,
        iconURL: URL? = nil
    ) {
        self.channelID = channelID
        self.start = start
        self.stop = stop
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.categories = categories
        self.episodeNumber = episodeNumber
        self.iconURL = iconURL
    }

    /// Identifier unique per channel and start time.
    public var id: String { "\(channelID)|\(Int64(start.timeIntervalSince1970))" }

    /// Length of the programme in seconds (never negative).
    public var duration: TimeInterval { max(0, stop.timeIntervalSince(start)) }

    /// `true` if the programme is on air at `date` (`start <= date < stop`).
    public func isAiring(at date: Date) -> Bool {
        start <= date && date < stop
    }

    /// Fraction elapsed at `date`, clamped to `0...1`.
    public func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / duration))
    }
}
