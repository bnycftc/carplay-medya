import CarMediaKit
import MediaPlayer
import UIKit

// TODO(iOS 27): Replace this whole file with the iOS 27 Now Playing framework
// (`MediaSession` / `RemoteMediaSessionExtension`, plan §5) behind `if #available(iOS 27, *)`,
// keeping this implementation for iOS 17–26.
// WARNING: Do not mix the two. Using MPNowPlayingInfoCenter / MPRemoteCommandCenter together with
// the new framework in the same process is undefined behavior — switch completely per OS version.

/// Publishes lock-screen / CarPlay "Now Playing" metadata and handles remote commands (iOS 17–26).
///
/// This is the only file that touches `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`.
/// `AVPlayerViewController.updatesNowPlayingInfoCenter` is turned off so there is a single writer.
/// Used only from `PlaybackController` (main actor); command handlers hop to the main actor themselves.
final class NowPlayingInfoPublisher {
    private var isConfigured = false

    /// Registers remote command handlers once. Handlers hop to the main actor and call the shared controller.
    func configureRemoteCommands() {
        guard !isConfigured else { return }
        isConfigured = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { _ in
            Task { @MainActor in PlaybackController.shared.resume() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in PlaybackController.shared.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in PlaybackController.shared.togglePlayPause() }
            return .success
        }
        center.stopCommand.addTarget { _ in
            Task { @MainActor in PlaybackController.shared.stop() }
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in PlaybackController.shared.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in PlaybackController.shared.playPrevious() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in PlaybackController.shared.seek(to: position) }
            return .success
        }

        // Not meaningful for channels.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        center.changePlaybackRateCommand.isEnabled = false

        let skip = UserDefaults.standard.object(forKey: SettingsKeys.channelSkipEnabled) as? Bool ?? true
        setSkipEnabled(skip)
    }

    /// Enables or disables next/previous channel commands.
    func setSkipEnabled(_ enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = enabled
        center.previousTrackCommand.isEnabled = enabled
    }

    /// Mirrors `state` to the Now Playing info center.
    func update(_ state: NowPlayingState, artwork: UIImage?) {
        guard let channel = state.channel else {
            clear()
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: channel.title,
            MPNowPlayingInfoPropertyIsLiveStream: state.isLive,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: NSNumber(
                value: (state.isAudioOnly ? MPNowPlayingInfoMediaType.audio : MPNowPlayingInfoMediaType.video).rawValue
            ),
        ]
        if let subtitle = state.subtitle {
            info[MPMediaItemPropertyArtist] = subtitle
        }
        if !state.isLive {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = state.elapsed
            if let duration = state.duration {
                info[MPMediaItemPropertyPlaybackDuration] = duration
            }
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = state.canSeek
    }

    /// Removes Now Playing metadata (nothing is playing).
    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
