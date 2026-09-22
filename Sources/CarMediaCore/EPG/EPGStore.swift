import Foundation

/// In-memory programme guide indexed by channel id, with "now / next" lookups.
///
/// Programmes of each channel are kept sorted by start time; lookups use binary search.
/// Programmes whose `stop` is missing or not after `start` get the next programme's start
/// as their end (or start + 1 hour for the last one).
public struct EPGStore: Sendable {
    /// Channels declared by the guide, keyed by id.
    public private(set) var channels: [String: EPGChannel] = [:]
    private var programmesByChannel: [String: [Programme]] = [:]
    private var lowercasedIDs: [String: String] = [:]
    private var displayNameIndex: [String: String] = [:]

    /// Default length assumed for a final programme without a stop time.
    public static let fallbackDuration: TimeInterval = 3600

    /// Creates a store.
    public init(channels: [EPGChannel] = [], programmes: [Programme] = []) {
        add(channels: channels)
        add(programmes: programmes)
    }

    /// Number of programmes across all channels.
    public var programmeCount: Int { programmesByChannel.values.reduce(0) { $0 + $1.count } }

    /// Channel ids that have at least one programme.
    public var channelIDsWithProgrammes: [String] { Array(programmesByChannel.keys) }

    /// Adds or replaces channel declarations.
    public mutating func add(channels newChannels: [EPGChannel]) {
        for channel in newChannels {
            channels[channel.id] = channel
            lowercasedIDs[channel.id.lowercased()] = lowercasedIDs[channel.id.lowercased()] ?? channel.id
            for name in channel.displayNames {
                let key = Self.normalizeName(name)
                if !key.isEmpty, displayNameIndex[key] == nil { displayNameIndex[key] = channel.id }
            }
        }
    }

    /// Adds programmes; affected channels are re-sorted and duplicates (same start) removed.
    public mutating func add(programmes newProgrammes: [Programme]) {
        guard !newProgrammes.isEmpty else { return }
        var touched = Set<String>()
        for programme in newProgrammes {
            programmesByChannel[programme.channelID, default: []].append(programme)
            touched.insert(programme.channelID)
        }
        for id in touched {
            lowercasedIDs[id.lowercased()] = lowercasedIDs[id.lowercased()] ?? id
            programmesByChannel[id] = Self.normalize(programmesByChannel[id] ?? [])
        }
    }

    /// Removes programmes that ended before `date` (keeps memory bounded for long-running sessions).
    public mutating func prune(before date: Date) {
        for (id, list) in programmesByChannel {
            programmesByChannel[id] = list.filter { $0.stop > date }
        }
    }

    // MARK: Lookups

    /// All programmes of a channel, sorted by start.
    public func programmes(for channelID: String) -> [Programme] {
        guard let id = resolveKey(channelID) else { return [] }
        return programmesByChannel[id] ?? []
    }

    /// The programme on air at `date`, if any.
    public func current(for channelID: String, at date: Date = Date()) -> Programme? {
        let list = programmes(for: channelID)
        // Index of the first programme starting after `date`; the candidate is the one before it.
        let index = Self.firstIndex(in: list) { $0.start > date }
        guard index > 0 else { return nil }
        let candidate = list[index - 1]
        return candidate.isAiring(at: date) ? candidate : nil
    }

    /// The first programme starting after `date`.
    public func next(for channelID: String, at date: Date = Date()) -> Programme? {
        let list = programmes(for: channelID)
        let index = Self.firstIndex(in: list) { $0.start > date }
        return index < list.count ? list[index] : nil
    }

    /// Programmes overlapping `range` (`start < range.upperBound && stop > range.lowerBound`).
    public func programmes(for channelID: String, in range: Range<Date>) -> [Programme] {
        let list = programmes(for: channelID)
        let end = Self.firstIndex(in: list) { $0.start >= range.upperBound }
        return list[..<end].filter { $0.stop > range.lowerBound }
    }

    // MARK: Channel mapping

    /// Resolves the guide channel id for an M3U channel.
    ///
    /// Order: exact `tvg-id`, case-insensitive `tvg-id`, then `tvg-name` or title matched
    /// against `<display-name>` values (case/diacritic/space-insensitive).
    public func resolveChannelID(for channel: Channel) -> String? {
        resolveChannelID(tvgID: channel.tvgID, tvgName: channel.tvgName, title: channel.title)
    }

    /// Resolves the guide channel id from M3U-style identifiers.
    public func resolveChannelID(tvgID: String?, tvgName: String? = nil, title: String? = nil) -> String? {
        if let tvgID, !tvgID.isEmpty, let id = resolveKey(tvgID) { return id }
        for name in [tvgName, title].compactMap({ $0 }) {
            let key = Self.normalizeName(name)
            if !key.isEmpty, let id = displayNameIndex[key] { return id }
        }
        return nil
    }

    // MARK: Helpers

    private func resolveKey(_ id: String) -> String? {
        if programmesByChannel[id] != nil || channels[id] != nil { return id }
        return lowercasedIDs[id.lowercased()]
    }

    static func normalize(_ list: [Programme]) -> [Programme] {
        var sorted = list.sorted { $0.start < $1.start }
        var deduped: [Programme] = []
        deduped.reserveCapacity(sorted.count)
        for programme in sorted {
            if let last = deduped.last, last.start == programme.start {
                continue // keep the first programme for a given start time
            }
            deduped.append(programme)
        }
        sorted = deduped
        for i in sorted.indices where sorted[i].stop <= sorted[i].start {
            sorted[i].stop = i + 1 < sorted.count
                ? sorted[i + 1].start
                : sorted[i].start.addingTimeInterval(fallbackDuration)
        }
        return sorted
    }

    /// Binary search: first index where `predicate` is true (predicate must be monotonic).
    static func firstIndex(in list: [Programme], where predicate: (Programme) -> Bool) -> Int {
        var low = 0
        var high = list.count
        while low < high {
            let mid = (low + high) / 2
            if predicate(list[mid]) { high = mid } else { low = mid + 1 }
        }
        return low
    }

    static func normalizeName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
    }
}
