import SwiftUI

@main
struct CarMedyaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared
    @StateObject private var playback = PlaybackController.shared
    @StateObject private var motion = MotionMonitor.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(playback)
                .environmentObject(motion)
        }
    }
}

/// `UserDefaults` / `@AppStorage` keys.
enum SettingsKeys {
    static let onboardingCompleted = "onboardingCompleted"
    static let motionPolicyEnabled = "motionPolicyEnabled"
    static let channelSkipEnabled = "channelSkipEnabled"
}

/// Fixed links shown in Settings.
enum AppLinks {
    // TODO: Replace with the real privacy policy / support pages before App Review.
    static let privacyPolicy = URL(string: "https://example.com/privacy")!
    static let support = URL(string: "https://example.com/support")!
}
