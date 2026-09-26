import Foundation
import CarMediaCore

/// Where a programme sits relative to "now".
public enum GuideEntryState: String, Sendable, Hashable {
    /// Already over.
    case past
    /// On air.
    case live
    /// Not started yet.
    case upcoming
}

/// One row of a channel's schedule.
public struct GuideEntry: Sendable, Hashable, Identifiable {
    /// The programme.
    public var programme: Programme
    /// Past, live or upcoming.
    public var state: GuideEntryState
    /// Progress 0…1 (only meaningful when live).
    public var progress: Double
    /// `HH:mm–HH:mm`.
    public var timeRange: String
    /// `true` when the programme can be replayed from the channel's archive.
    public var canReplay: Bool

    /// Programme id.
    public var id: String { programme.id }
}

/// Programmes of one calendar day.
public struct GuideDay: Sendable, Hashable, Identifiable {
    /// Start of the day in the presenter's time zone.
    public var date: Date
    /// Offset from today (−1 yesterday, 0 today, 1 tomorrow…).
    public var dayOffset: Int
    /// Programmes in start order.
    public var entries: [GuideEntry]

    /// `yyyy-MM-dd`-like stable id.
    public var id: String { String(Int(date.timeIntervalSince1970)) }
}

/// Builds the per-channel schedule shown in the guide screen, including archive availability.
public struct GuidePresenter: Sendable {
    private let timeZone: TimeZone
    private let times: EPGPresenter

    /// Creates a presenter using `timeZone` for day boundaries and times.
    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
        times = EPGPresenter(timeZone: timeZone)
    }

    /// Whether `channel` has any programme in `store`.
    public func hasGuide(_ channel: Channel, in store: EPGStore) -> Bool {
        guard let id = store.resolveChannelID(for: channel) else { return false }
        return !store.programmes(for: id).isEmpty
    }

    /// The schedule of `channel` from `daysBack` days before to `daysAhead` days after the day of `now`,
    /// grouped by day. Days without programmes are omitted.
    public func schedule(
        for channel: Channel,
        in store: EPGStore,
        now: Date,
        daysBack: Int = 1,
        daysAhead: Int = 1
    ) -> [GuideDay] {
        guard let channelID = store.resolveChannelID(for: channel) else { return [] }
        let calendar = self.calendar
        let today = calendar.startOfDay(for: now)
        guard let rangeStart = calendar.date(byAdding: .day, value: -max(0, daysBack), to: today),
              let rangeEnd = calendar.date(byAdding: .day, value: max(0, daysAhead) + 1, to: today),
              rangeStart < rangeEnd else { return [] }
        let programmes = store.programmes(for: channelID, in: rangeStart..<rangeEnd)
        var days: [Date: [GuideEntry]] = [:]
        for programme in programmes {
            let state: GuideEntryState
            if programme.stop <= now {
                state = .past
            } else if programme.start <= now {
                state = .live
            } else {
                state = .upcoming
            }
            let entry = GuideEntry(
                programme: programme,
                state: state,
                progress: state == .live ? programme.progress(at: now) : (state == .past ? 1 : 0),
                timeRange: times.timeText(programme.start) + "\u{2013}" + times.timeText(programme.stop),
                canReplay: state == .past && CatchupURLBuilder.isAvailable(
                    for: channel, programmeStart: programme.start, programmeEnd: programme.stop, now: now
                )
            )
            let day = max(calendar.startOfDay(for: programme.start), rangeStart)
            days[day, default: []].append(entry)
        }
        return days.keys.sorted().map { day in
            let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
            return GuideDay(date: day, dayOffset: offset, entries: days[day] ?? [])
        }
    }

    /// The live entry of a schedule, if any (used to scroll the list to "now").
    public static func liveEntry(in days: [GuideDay]) -> GuideEntry? {
        for day in days {
            if let entry = day.entries.first(where: { $0.state == .live }) { return entry }
        }
        return nil
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
