import CarMediaKit
import Combine
import Foundation

/// Keeps the last CarPlay session's video facts (``CarVideoSnapshot``) for Settings > "Araç ekranında video".
///
/// Stored as JSON in `UserDefaults` (no URLs, names or secrets), written only when a value changes.
@MainActor
final class CarVideoDiagnostics: ObservableObject {
    static let shared = CarVideoDiagnostics()

    @Published private(set) var snapshot: CarVideoSnapshot?

    private init() {
        if let data = UserDefaults.standard.data(forKey: SettingsKeys.carVideoSnapshot) {
            snapshot = try? JSONDecoder().decode(CarVideoSnapshot.self, from: data)
        }
        // A session left open by a process kill (no didDisconnect) cannot still be running in a new
        // process; close it so phone-only AirPlay is not counted as car video. A live CarPlay
        // connection replaces the snapshot via recordConnect anyway.
        if var current = snapshot, current.isConnected {
            current.close(at: Date())
            snapshot = current
            save()
        }
    }

    /// A CarPlay session started: replaces the previous session's snapshot.
    func recordConnect(systemSupportsAPI: Bool, carSupportsVideo: Bool?) {
        snapshot = CarVideoSnapshot(
            connectedAt: Date(),
            systemSupportsAPI: systemSupportsAPI,
            carSupportsVideo: carSupportsVideo
        )
        save()
    }

    /// Latest `supportsVideoPlayback` value.
    func recordSample(carSupportsVideo: Bool) {
        guard var current = snapshot else { return }
        if current.sample(carSupportsVideo: carSupportsVideo) {
            snapshot = current
            save()
        }
    }

    /// A row marked `.video` was played.
    func recordVideoPlay() {
        guard var current = snapshot else { return }
        if current.markVideoPlayed() {
            snapshot = current
            save()
        }
    }

    /// `AVPlayer.isExternalPlaybackActive` changed.
    func recordExternalPlayback(_ active: Bool) {
        guard var current = snapshot else { return }
        if current.markExternalPlayback(active) {
            snapshot = current
            save()
        }
    }

    /// The CarPlay session ended.
    func recordDisconnect() {
        guard var current = snapshot, current.isConnected else { return }
        current.close(at: Date())
        snapshot = current
        save()
    }

    private func save() {
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: SettingsKeys.carVideoSnapshot)
    }
}
