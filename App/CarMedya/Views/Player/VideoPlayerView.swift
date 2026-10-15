import AVKit
import Combine
import SwiftUI
import UIKit

/// `AVPlayerViewController` wrapper: PiP, AirPlay video and background audio.
///
/// Now Playing metadata is published by `NowPlayingInfoPublisher`, so the controller's own
/// `updatesNowPlayingInfoCenter` is off (single writer).
struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var allowsPictureInPicture = true

    func makeCoordinator() -> Coordinator {
        Coordinator(player: player)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = allowsPictureInPicture
        controller.canStartPictureInPictureAutomaticallyFromInline = allowsPictureInPicture
        controller.updatesNowPlayingInfoCenter = false
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.videoGravity = .resizeAspect
        context.coordinator.attach(controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player, !context.coordinator.isDetachedForBackground {
            controller.player = player
        }
        controller.allowsPictureInPicturePlayback = allowsPictureInPicture
        controller.canStartPictureInPictureAutomaticallyFromInline = allowsPictureInPicture
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        private let player: AVPlayer
        private weak var controller: AVPlayerViewController?
        private var isPictureInPictureActive = false
        private(set) var isDetachedForBackground = false
        private var observers = Set<AnyCancellable>()

        init(player: AVPlayer) {
            self.player = player
        }

        func attach(_ controller: AVPlayerViewController) {
            self.controller = controller
            // A player attached to a visible layer is paused by iOS in the background.
            // Detach it (unless PiP is running) so audio keeps playing, reattach on return.
            NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.enteredBackground() }
                .store(in: &observers)
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.willEnterForeground() }
                .store(in: &observers)
        }

        func detach() {
            observers.removeAll()
        }

        private func enteredBackground() {
            guard !isPictureInPictureActive, !player.isExternalPlaybackActive, let controller else { return }
            controller.player = nil
            isDetachedForBackground = true
        }

        private func willEnterForeground() {
            guard isDetachedForBackground, let controller else { return }
            controller.player = player
            isDetachedForBackground = false
        }

        // MARK: AVPlayerViewControllerDelegate

        func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            isPictureInPictureActive = true
        }

        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            isPictureInPictureActive = false
        }

        func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(
            _ playerViewController: AVPlayerViewController
        ) -> Bool {
            false
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            PlaybackController.shared.isPlayerPresented = true
            completionHandler(true)
        }
    }
}

/// AirPlay route button that prefers video-capable receivers.
struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = .label
        view.activeTintColor = .systemBlue
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
