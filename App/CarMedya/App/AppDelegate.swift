import CarPlay
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // CarPlay can launch the app without the phone UI: load sources and register remote commands now.
        AppModel.shared.start()
        _ = PlaybackController.shared
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            let configuration = UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
            configuration.sceneClass = CPTemplateApplicationScene.self
            configuration.delegateClass = CarPlaySceneDelegate.self
            return configuration
        }
        // Phone scene: no delegate class, so SwiftUI installs its own and drives the WindowGroup.
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }
}
