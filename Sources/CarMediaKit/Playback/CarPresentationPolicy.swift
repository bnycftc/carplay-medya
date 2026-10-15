import Foundation

/// How the app asks CarPlay to present the current item.
public enum CarPresentation: Sendable, Equatable {
    /// Audio only (Now Playing shows artwork and metadata).
    case audio
    /// Video on the car screen (AirPlay video presented by the system).
    case video
}

/// What tapping a CarPlay list row will do, as shown by the row's playback configuration.
public enum CarRowAction: Sendable, Equatable {
    case play
    case pause
}

/// What the app does when a CarPlay list row is tapped.
public enum CarRowTapIntent: Sendable, Equatable {
    /// Start playing the row's channel.
    case start
    /// Resume the paused current channel.
    case resume
    /// Pause the playing current channel.
    case pause
}

/// Decides how items are presented in CarPlay. Pure logic; the CarPlay layer feeds it the session state.
///
/// The app declares only the CarPlay audio entitlement, so it stays visible in every vehicle. Video on the
/// car screen is AirPlay video presented by the system, and only works where the car supports it
/// (`CPSessionConfiguration.supportsVideoPlayback`, which can change during the session).
public struct CarPresentationPolicy: Sendable, Equatable {
    /// `CPSessionConfiguration.supportsVideoPlayback` (always `false` before iOS 27).
    public var carSupportsVideo: Bool
    /// The "Park halinde araç ekranında video" setting (off by default).
    public var userAllowsVideoInCar: Bool

    /// Creates a policy.
    public init(carSupportsVideo: Bool = false, userAllowsVideoInCar: Bool = false) {
        self.carSupportsVideo = carSupportsVideo
        self.userAllowsVideoInCar = userAllowsVideoInCar
    }

    /// Whether video may be offered on the car screen right now.
    public var videoAvailable: Bool { carSupportsVideo && userAllowsVideoInCar }

    /// `.video` only when video is available and the item has a picture; audio-only items always present as audio.
    public func presentation(isAudioOnly: Bool) -> CarPresentation {
        videoAvailable && !isAudioOnly ? .video : .audio
    }

    /// Action a row advertises: the current item that is playing or loading offers pause, everything else play.
    public static func rowAction(isCurrent: Bool, isActive: Bool) -> CarRowAction {
        isCurrent && isActive ? .pause : .play
    }

    /// Action performed when a row is tapped.
    /// - Parameters:
    ///   - isActive: playing or loading.
    ///   - isPaused: paused (not failed or idle).
    public static func tapIntent(isCurrent: Bool, isActive: Bool, isPaused: Bool) -> CarRowTapIntent {
        if isCurrent && isActive { return .pause }
        if isCurrent && isPaused { return .resume }
        return .start
    }
}
