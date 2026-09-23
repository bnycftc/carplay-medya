import CarMediaCore
import CarMediaKit
import SwiftUI

/// Full-screen phone player: video (hidden while driving), AirPlay, guide info and errors.
struct PlayerScreen: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var motion: MotionMonitor

    var body: some View {
        let state = playback.state
        VStack(spacing: 0) {
            header(state)
            ZStack {
                Color.black
                if state.isAudioOnly {
                    audioArtwork(state)
                } else {
                    VideoPlayerView(player: playback.player, allowsPictureInPicture: motion.allowsVideo)
                    if !motion.allowsVideo {
                        drivingCover
                    }
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    details(state)
                    if let failure = state.failure {
                        failureView(failure, phase: state.phase)
                    }
                    controls(state)
                }
                .padding()
            }
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear { motion.beginMonitoring() }
        .onDisappear { motion.endMonitoring() }
    }

    // MARK: Parts

    private func header(_ state: NowPlayingState) -> some View {
        HStack(spacing: 8) {
            Button {
                playback.isPlayerPresented = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Kapat"))
            Spacer()
            if let channel = state.channel {
                let isFavorite = model.isFavorite(channel.id)
                Button {
                    model.toggleFavorite(channel.id)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .tint(isFavorite ? .yellow : .accentColor)
                .accessibilityLabel(isFavorite ? Text("Favorilerden çıkar") : Text("Favorilere ekle"))
            }
            RoutePickerView()
                .frame(width: 44, height: 44)
                .accessibilityLabel(Text("AirPlay"))
        }
        .padding(.horizontal, 8)
    }

    private var drivingCover: some View {
        VStack(spacing: 12) {
            Image(systemName: "car.fill")
                .font(.largeTitle)
            Text("Sürüş sırasında video gösterilmez")
                .font(.headline)
            Text("Ses çalmaya devam ediyor.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func audioArtwork(_ state: NowPlayingState) -> some View {
        LogoView(url: state.channel?.logoURL, isRadio: true)
            .frame(width: 140, height: 140)
    }

    private func details(_ state: NowPlayingState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: state.title)
                .font(.title3.bold())
            if let group = state.channel?.groupTitle {
                Text(verbatim: group)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let channel = state.channel {
                TimelineView(.everyMinute) { context in
                    if let summary = model.epgSummary(for: channel, at: context.date) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let now = summary.nowLine {
                                Text("Şimdi: \(now)").font(.subheadline)
                                ProgressView(value: summary.progress)
                            }
                            if let next = summary.nextLine {
                                Text("Sonra: \(next)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if state.phase == .loading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Yükleniyor…").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func failureView(_ failure: UserFacingError, phase: NowPlayingState.Phase) -> some View {
        var detail: String?
        if case .failed(_, let text) = phase { detail = text }
        var canRetry = true
        if case .unsupported = failure { canRetry = false }
        return VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(verbatim: failure.message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.red)
            if let detail {
                // Already redacted (no passwords), useful when reporting a problem.
                Text(verbatim: detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(4)
            }
            if canRetry {
                Button("Tekrar dene") { playback.retry() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func controls(_ state: NowPlayingState) -> some View {
        HStack(spacing: 40) {
            Button {
                playback.playPrevious()
            } label: {
                Image(systemName: "backward.fill").font(.title2)
            }
            .disabled(state.previousChannel == nil)
            .accessibilityLabel(Text("Önceki kanal"))

            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: state.isPlaying || state.phase == .loading ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
            }
            .accessibilityLabel(state.isPlaying ? Text("Duraklat") : Text("Oynat"))

            Button {
                playback.playNext()
            } label: {
                Image(systemName: "forward.fill").font(.title2)
            }
            .disabled(state.nextChannel == nil)
            .accessibilityLabel(Text("Sonraki kanal"))
        }
        .frame(maxWidth: .infinity)
    }
}
