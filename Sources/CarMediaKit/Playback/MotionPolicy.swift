import Foundation

/// Decides whether video may be shown on the phone, based on vehicle speed, with hysteresis.
///
/// The vehicle itself blocks video on the CarPlay screen while driving; this is the app's own
/// additional rule for the phone screen (plan §2.3, "Sürücü güvenliği yerleşik"):
/// - "moving" starts once speed reaches ``movingThreshold`` (default 8 km/h),
/// - "moving" ends only once speed drops to ``stoppedThreshold`` (default 3 km/h) or below,
///   so GPS jitter around a single threshold does not flip the screen on and off,
/// - invalid readings (negative speed, as `CLLocation.speed` reports when unknown) keep the current state,
/// - video is hidden only when GPS has confirmed movement; an unknown speed (no location permission,
///   no fix yet) never hides it, so a parked car with CarPlay connected still shows video on the phone.
///   The car itself keeps video off the CarPlay screen while driving.
public struct MotionPolicy: Sendable, Equatable {
    /// Speed (m/s) at or above which the vehicle counts as moving.
    public let movingThreshold: Double
    /// Speed (m/s) at or below which a moving vehicle counts as stopped again.
    public let stoppedThreshold: Double
    /// When `false`, video is always allowed (user turned the safety rule off).
    public var isEnabled: Bool

    /// Current hysteresis state.
    public private(set) var isMoving = false
    /// Whether a valid speed reading has been received since the last reset.
    public private(set) var hasSpeedReading = false
    /// Whether a CarPlay session is connected.
    public private(set) var isCarPlayConnected = false

    /// Default "moving" threshold in km/h.
    public static let defaultMovingKmh = 8.0
    /// Default "stopped" threshold in km/h.
    public static let defaultStoppedKmh = 3.0

    /// Creates a policy with thresholds in km/h. `stoppedKmh` is clamped to be at most `movingKmh`.
    public init(movingKmh: Double = MotionPolicy.defaultMovingKmh,
                stoppedKmh: Double = MotionPolicy.defaultStoppedKmh,
                isEnabled: Bool = true) {
        let moving = max(0, movingKmh) / 3.6
        self.movingThreshold = moving
        self.stoppedThreshold = min(max(0, stoppedKmh) / 3.6, moving)
        self.isEnabled = isEnabled
    }

    /// Whether video may be shown right now.
    public var allowsVideo: Bool {
        guard isEnabled else { return true }
        return !isMoving
    }

    /// Feeds a speed reading in m/s. Negative or non-finite values mean "unknown" and are ignored.
    /// - Returns: the new ``allowsVideo`` value.
    @discardableResult
    public mutating func update(speed metersPerSecond: Double) -> Bool {
        guard metersPerSecond.isFinite, metersPerSecond >= 0 else { return allowsVideo }
        hasSpeedReading = true
        if isMoving {
            if metersPerSecond <= stoppedThreshold { isMoving = false }
        } else if metersPerSecond >= movingThreshold {
            isMoving = true
        }
        return allowsVideo
    }

    /// Records CarPlay connection changes. Disconnecting forgets the speed state.
    /// - Returns: the new ``allowsVideo`` value.
    @discardableResult
    public mutating func update(carPlayConnected: Bool) -> Bool {
        if isCarPlayConnected != carPlayConnected, !carPlayConnected {
            reset()
        }
        isCarPlayConnected = carPlayConnected
        return allowsVideo
    }

    /// Forgets speed history (e.g. when location updates stop).
    public mutating func reset() {
        isMoving = false
        hasSpeedReading = false
    }
}
