import Foundation
import CarMediaCore

/// "Now / next" information for one channel, ready to display.
///
/// Texts are language-neutral (times and titles); the app adds localized labels such as "Şimdi" / "Sonra".
public struct EPGSummary: Sendable, Equatable {
    /// Programme on air.
    public var now: Programme?
    /// Following programme.
    public var next: Programme?
    /// Fraction of `now` elapsed (`0...1`), `0` when nothing is on air.
    public var progress: Double
    /// Whole minutes left of `now` (rounded up), `nil` when nothing is on air.
    public var minutesRemaining: Int?
    /// `"20:00–21:00"` for `now`.
    public var nowTimeRange: String?
    /// `"21:00"` start time of `next`.
    public var nextStartTime: String?

    /// `"20:00–21:00 Haberler"`, or `nil`.
    public var nowLine: String? {
        guard let now else { return nil }
        return [nowTimeRange, now.title].compactMap { $0 }.joined(separator: " ")
    }

    /// `"21:00 Film"`, or `nil`.
    public var nextLine: String? {
        guard let next else { return nil }
        return [nextStartTime, next.title].compactMap { $0 }.joined(separator: " ")
    }
}

/// Formats guide data for channel rows, the player and CarPlay list items.
public struct EPGPresenter: Sendable {
    private let timeZone: TimeZone

    /// Creates a presenter. Times are shown as 24-hour `HH:mm` in `timeZone`.
    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    /// Summary for `channel` at `date`, or `nil` if the guide knows nothing about it.
    public func summary(for channel: Channel, in store: EPGStore, at date: Date) -> EPGSummary? {
        guard let id = store.resolveChannelID(for: channel) else { return nil }
        return summary(channelID: id, in: store, at: date)
    }

    /// Summary for a guide channel id at `date`, or `nil` if there is neither a current nor a next programme.
    public func summary(channelID: String, in store: EPGStore, at date: Date) -> EPGSummary? {
        let now = store.current(for: channelID, at: date)
        let next = store.next(for: channelID, at: date)
        guard now != nil || next != nil else { return nil }
        return EPGSummary(
            now: now,
            next: next,
            progress: now?.progress(at: date) ?? 0,
            minutesRemaining: now.map { Self.minutesRemaining(until: $0.stop, from: date) },
            nowTimeRange: now.map { timeText($0.start) + "\u{2013}" + timeText($0.stop) },
            nextStartTime: next.map { timeText($0.start) }
        )
    }

    /// `HH:mm` in the presenter's time zone.
    public func timeText(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Minutes until `end`, rounded up, never negative.
    public static func minutesRemaining(until end: Date, from date: Date) -> Int {
        let seconds = end.timeIntervalSince(date)
        guard seconds > 0 else { return 0 }
        return Int((seconds / 60).rounded(.up))
    }
}
