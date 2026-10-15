import Foundation

/// Facts from the last CarPlay session, kept so they can be read on the phone after leaving the car.
///
/// Holds no secrets (no URLs, names or credentials); the app stores it in `UserDefaults`.
public struct CarVideoSnapshot: Sendable, Equatable, Codable {
    public var connectedAt: Date
    public var disconnectedAt: Date?
    /// The CarPlay video API was available on this iOS (the app's iOS gate passed).
    public var systemSupportsAPI: Bool
    /// Last sampled `CPSessionConfiguration.supportsVideoPlayback`; nil when the API was unavailable.
    public var carSupportsVideo: Bool?
    /// A row marked `.video` was played in this session.
    public var playedVideoItem: Bool
    /// `AVPlayer.isExternalPlaybackActive` became true while this session was open.
    public var externalPlaybackSeen: Bool

    /// Creates a snapshot for a session that connected at `connectedAt`.
    public init(
        connectedAt: Date,
        systemSupportsAPI: Bool,
        carSupportsVideo: Bool?,
        disconnectedAt: Date? = nil,
        playedVideoItem: Bool = false,
        externalPlaybackSeen: Bool = false
    ) {
        self.connectedAt = connectedAt
        self.disconnectedAt = disconnectedAt
        self.systemSupportsAPI = systemSupportsAPI
        self.carSupportsVideo = carSupportsVideo
        self.playedVideoItem = playedVideoItem
        self.externalPlaybackSeen = externalPlaybackSeen
    }

    /// Whether the session is still open.
    public var isConnected: Bool { disconnectedAt == nil }

    /// Records the latest `supportsVideoPlayback` value. Returns true when the stored value changed
    /// (the caller persists only then).
    @discardableResult
    public mutating func sample(carSupportsVideo value: Bool) -> Bool {
        if carSupportsVideo == value { return false }
        carSupportsVideo = value
        return true
    }

    /// Records that a row marked `.video` was played. Returns true when the flag flipped.
    @discardableResult
    public mutating func markVideoPlayed() -> Bool {
        if playedVideoItem { return false }
        playedVideoItem = true
        return true
    }

    /// Only `true` is recorded, only while connected; returns true when the flag flipped.
    @discardableResult
    public mutating func markExternalPlayback(_ active: Bool) -> Bool {
        guard active, isConnected, !externalPlaybackSeen else { return false }
        externalPlaybackSeen = true
        return true
    }

    /// Marks the session as closed.
    public mutating func close(at date: Date) {
        disconnectedAt = date
    }
}

/// What the last CarPlay session says about video on the car display. Pure logic; the app shows it in Settings.
public enum CarVideoDiagnosis: Sendable, Equatable, CaseIterable {
    /// No CarPlay session recorded yet.
    case notConnectedYet
    /// The iOS version has no CarPlay video API.
    case systemTooOld
    /// The car did not report video support (`supportsVideoPlayback` false or unknown).
    case carHasNoVideo
    /// The car supports video but "Park halinde araç ekranında video" is off.
    case settingOff
    /// Everything is in place; no video row played yet.
    case ready
    /// A video row played but external playback never became active.
    case videoNotShown
    /// External playback (AirPlay video to the car display) was active.
    case videoShown

    /// `settingOn` is the current toggle value (the owner may change it after leaving the car).
    /// The car check precedes the setting check: without car support the setting cannot help.
    public init(snapshot: CarVideoSnapshot?, settingOn: Bool) {
        guard let s = snapshot else { self = .notConnectedYet; return }
        guard s.systemSupportsAPI else { self = .systemTooOld; return }
        guard s.carSupportsVideo == true else { self = .carHasNoVideo; return }
        guard settingOn else { self = .settingOff; return }
        if s.externalPlaybackSeen { self = .videoShown; return }
        self = s.playedVideoItem ? .videoNotShown : .ready
    }
}
