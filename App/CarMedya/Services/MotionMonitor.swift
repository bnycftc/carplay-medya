import CarMediaKit
import CoreLocation
import Foundation

/// Feeds ``MotionPolicy`` with GPS speed and the CarPlay connection state.
///
/// Location updates run only while a video screen is visible (``beginMonitoring()`` / ``endMonitoring()``)
/// and only with "when in use" permission. Locations are never stored or sent anywhere.
@MainActor
final class MotionMonitor: NSObject, ObservableObject {
    static let shared = MotionMonitor()

    /// Whether the phone may show video right now.
    @Published private(set) var allowsVideo = true
    /// Location permission.
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// Whether the safety rule is on (mirrors Settings).
    @Published private(set) var isEnabled: Bool

    private var policy: MotionPolicy
    private let manager = CLLocationManager()
    private var consumers = 0

    private override init() {
        let enabled = UserDefaults.standard.object(forKey: SettingsKeys.motionPolicyEnabled) as? Bool ?? true
        isEnabled = enabled
        policy = MotionPolicy(isEnabled: enabled)
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorization = manager.authorizationStatus
        publish()
    }

    // MARK: Inputs

    /// Turns the safety rule on or off (persisted by the Settings screen).
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        policy.isEnabled = enabled
        updateLocationUpdates()
        publish()
    }

    /// Called by the CarPlay scene delegate.
    func setCarPlayConnected(_ connected: Bool) {
        policy.update(carPlayConnected: connected)
        publish()
    }

    /// A video surface became visible.
    func beginMonitoring() {
        consumers += 1
        if authorization == .notDetermined && isEnabled {
            manager.requestWhenInUseAuthorization()
        }
        updateLocationUpdates()
    }

    /// A video surface disappeared.
    func endMonitoring() {
        consumers = max(0, consumers - 1)
        updateLocationUpdates()
    }

    /// Asks for "when in use" permission (Settings button).
    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    // MARK: Internals

    private var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    private func updateLocationUpdates() {
        if consumers > 0 && isEnabled && isAuthorized {
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
            policy.reset()
            publish()
        }
    }

    fileprivate func apply(speed: Double) {
        policy.update(speed: speed)
        publish()
    }

    fileprivate func authorizationChanged(_ status: CLAuthorizationStatus) {
        authorization = status
        updateLocationUpdates()
    }

    private func publish() {
        if allowsVideo != policy.allowsVideo { allowsVideo = policy.allowsVideo }
    }
}

extension MotionMonitor: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let speed = locations.last?.speed else { return }
        Task { @MainActor in MotionMonitor.shared.apply(speed: speed) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in MotionMonitor.shared.authorizationChanged(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Speed stays "unknown"; MotionPolicy keeps its last state.
    }
}
