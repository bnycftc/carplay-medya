import Foundation

/// Automatic reconnection for live streams, which IPTV servers drop or stall regularly.
///
/// A failure (or a long stall) of a live stream schedules a retry after 2, 5 and then 10 seconds.
/// Once playback has run steadily for ``stableInterval`` the attempt counter starts over, so a
/// channel that drops once an hour always gets its three retries.
public struct ReconnectPolicy: Sendable, Equatable {
    /// Delays before each retry.
    public static let delays: [TimeInterval] = [2, 5, 10]
    /// Playing this long without trouble resets the attempt counter.
    public static let stableInterval: TimeInterval = 30
    /// A live stream buffering this long counts as a failure.
    public static let stallTimeout: TimeInterval = 15

    /// Retries used since the last reset.
    public private(set) var attempt = 0
    private var playingSince: Date?

    /// Creates a fresh policy.
    public init() {}

    /// Maximum number of retries.
    public static var maxAttempts: Int { delays.count }

    /// Playback (re)started at `date`.
    public mutating func markPlaying(at date: Date) {
        if playingSince == nil { playingSince = date }
    }

    /// Playback stopped playing (buffering, paused) at `date` without failing.
    public mutating func markInterrupted(at date: Date) {
        if let playingSince, date.timeIntervalSince(playingSince) >= Self.stableInterval {
            attempt = 0
        }
        self.playingSince = nil
    }

    /// A failure at `date`. Returns the delay before the next retry, or `nil` when retries are used up.
    public mutating func noteFailure(at date: Date) -> TimeInterval? {
        markInterrupted(at: date)
        guard attempt < Self.delays.count else { return nil }
        let delay = Self.delays[attempt]
        attempt += 1
        return delay
    }

    /// A new channel or a manual retry: start over.
    public mutating func reset() {
        attempt = 0
        playingSince = nil
    }
}
