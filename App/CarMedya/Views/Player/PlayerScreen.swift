import CarMediaCore
import CarMediaKit
import SwiftUI

/// Full-screen phone player: video (hidden while driving), AirPlay, guide info and errors.
struct PlayerScreen: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var motion: MotionMonitor
    @State private var showsChannelList = false

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
        .sheet(isPresented: $showsChannelList) {
            ChannelSwitcherSheet()
                .presentationDetents([.medium, .large])
        }
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
            sleepMenu(state)
            if state.queue.count > 1 {
                Button {
                    showsChannelList = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Kanal listesi"))
            }
            RoutePickerView()
                .frame(width: 44, height: 44)
                .accessibilityLabel(Text("AirPlay"))
        }
        .padding(.horizontal, 8)
    }

    private func sleepMenu(_ state: NowPlayingState) -> some View {
        Menu {
            ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                Button {
                    playback.setSleepTimer(minutes)
                } label: {
                    Text("\(minutes) dakika")
                }
            }
            if let channel = state.channel, state.isLive,
               let end = model.epgSummary(for: channel, at: Date())?.now?.stop {
                Button {
                    playback.setSleepTimer(until: end)
                } label: {
                    Text("Program bitince")
                }
            }
            if playback.sleepDeadline != nil {
                Divider()
                Button(role: .destructive) {
                    playback.setSleepTimer(nil)
                } label: {
                    Text("Zamanlayıcıyı kapat")
                }
            }
        } label: {
            Image(systemName: playback.sleepDeadline == nil ? "moon.zzz" : "moon.zzz.fill")
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text("Uyku zamanlayıcı"))
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
                    if let attempt = state.reconnectAttempt {
                        Text("Yayın koptu, yeniden bağlanılıyor (\(attempt)/\(ReconnectPolicy.maxAttempts))…")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Yükleniyor…").foregroundStyle(.secondary)
                    }
                }
            }
            if let deadline = playback.sleepDeadline {
                Label {
                    Text("Uyku zamanlayıcı: \(deadline, style: .timer)")
                } icon: {
                    Image(systemName: "moon.zzz.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
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


/// Channel list inside the player: switch channels without closing it.
struct ChannelSwitcherSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let queue = playback.state.queue
        let channels = model.library.filter(queue, query: query)
        NavigationStack {
            TimelineView(.everyMinute) { context in
                ScrollViewReader { proxy in
                    List(channels) { channel in
                        Button {
                            playback.play(channel, queue: queue, presentPlayer: true)
                            dismiss()
                        } label: {
                            ChannelRow(
                                title: channel.title,
                                logoURL: channel.logoURL,
                                isRadio: channel.isRadio,
                                summary: model.epgSummary(for: channel, at: context.date),
                                isFavorite: model.isFavorite(channel.id),
                                isCurrent: playback.state.channel?.id == channel.id
                            )
                        }
                        .id(channel.id)
                    }
                    .listStyle(.plain)
                    .onAppear {
                        if let current = playback.state.channel?.id {
                            proxy.scrollTo(current, anchor: .center)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: Text("Kanal ara"))
            .navigationTitle("Kanallar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}
