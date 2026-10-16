#if DEBUG
import AVFoundation
import CarMediaCore
import CarMediaKit
import Foundation
import os

/// DEBUG-only CarPlay smoke hook for the experimental CI job "carplay-sim" (.github/workflows/app.yml).
///
/// Does nothing unless the process was launched with `-carplaySmoke`; Release/TestFlight builds do not
/// contain this file's code at all. Everything is logged with subsystem `com.bnycftc.carmedya`, category
/// `carplay-smoke` (public: no URLs, names or secrets), so CI can read it with `log show`.
@MainActor
enum CarPlaySmoke {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-carplaySmoke")
    static let log = Logger(subsystem: "com.bnycftc.carmedya", category: "carplay-smoke")

    /// The first bundled sample that resolves to video (not audio-only), with its collection as the queue.
    static var firstVideoSample: (channel: Channel, queue: [Channel])? {
        let resolver = PlaybackURLResolver()
        for collection in SampleLibrary.content.collections {
            for item in collection.items where resolver.isAudioOnly(item.channel, isXtreamSource: false) == false {
                return (item.channel, collection.items.map(\.channel))
            }
        }
        return nil
    }

    /// Phone side, at launch: starts the first video sample (as a user would before plugging in the car),
    /// so the app is the Now Playing app when the simulated CarPlay display connects.
    static func startPhoneSide() {
        guard isEnabled else { return }
        // Real Bools in the app's own defaults: a `-carVideoEnabled YES` launch argument would be a String,
        // which the CarPlay delegate's `as? Bool` reads as false (and it would shadow these values).
        UserDefaults.standard.set(true, forKey: SettingsKeys.onboardingCompleted)
        UserDefaults.standard.set(true, forKey: SettingsKeys.carVideoEnabled)
        note("launch: iOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion), phone playback in 3 s")
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard let sample = firstVideoSample else {
                note("phone: no video sample in SampleContent.json")
                return
            }
            if PlaybackController.shared.state.channel == nil {
                PlaybackController.shared.play(sample.channel, queue: sample.queue, presentPlayer: false)
                note("phone: started \(label(sample.channel))")
            }
            try? await Task.sleep(for: .seconds(8))
            logPlayback(stage: "phone +11s")
        }
    }

    static func note(_ message: String) {
        log.notice("\(message, privacy: .public)")
    }

    /// Bundled sample ids are logged; a channel from the user's own sources is only reported as such.
    static func label(_ channel: Channel?) -> String {
        guard let channel else { return "none" }
        let isSample = SampleLibrary.content.collections.contains { collection in
            collection.items.contains { $0.channel.id == channel.id }
        }
        return isSample ? "sample:\(channel.id)" : "non-sample"
    }

    /// Playback state, AirPlay video (external playback) and the audio route, e.g. `CarAudio` when CarPlay owns it.
    static func logPlayback(stage: String) {
        let controller = PlaybackController.shared
        let state = controller.state
        let phase: String
        switch state.phase {
        case .idle: phase = "idle"
        case .loading: phase = "loading"
        case .playing: phase = "playing"
        case .paused: phase = "paused"
        case .failed(let kind, _): phase = "failed(\(kind))"
        }
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
        note(
            "playback [\(stage)]: channel=\(label(state.channel)) phase=\(phase) "
                + "timeControlStatus=\(controller.player.timeControlStatus.rawValue) "
                + "isExternalPlaybackActive=\(controller.player.isExternalPlaybackActive) route=\(outputs)"
        )
        if let snapshot = CarVideoDiagnostics.shared.snapshot,
           let data = try? JSONEncoder().encode(snapshot),
           let json = String(data: data, encoding: .utf8) {
            note("carVideoSnapshot: \(json)")
        } else {
            note("carVideoSnapshot: none")
        }
    }
}
#endif
