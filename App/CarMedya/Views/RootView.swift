import CarMediaKit
import SwiftUI

struct RootView: View {
    @AppStorage(SettingsKeys.onboardingCompleted) private var onboardingCompleted = false
    @EnvironmentObject private var playback: PlaybackController

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Kütüphane", systemImage: "rectangle.stack") }
            CatalogView()
                .tabItem { Label("Filmler ve Diziler", systemImage: "film.stack") }
            FavoritesView()
                .tabItem { Label("Favoriler", systemImage: "star") }
            SourcesView()
                .tabItem { Label("Kaynaklar", systemImage: "antenna.radiowaves.left.and.right") }
            SettingsView()
                .tabItem { Label("Ayarlar", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: $playback.isPlayerPresented) {
            PlayerScreen()
        }
        .overlay {
            // Kept on a separate view so its presentation never competes with the player's.
            Color.clear
                .allowsHitTesting(false)
                .fullScreenCover(isPresented: Binding(
                    get: { !onboardingCompleted },
                    set: { presented in if !presented { onboardingCompleted = true } }
                )) {
                    OnboardingView { onboardingCompleted = true }
                }
        }
    }
}

/// Adds the mini player above the tab bar of each tab.
struct NowPlayingInset: ViewModifier {
    @EnvironmentObject private var playback: PlaybackController

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if playback.state.isActive {
                NowPlayingBar()
            }
        }
    }
}

extension View {
    func nowPlayingInset() -> some View { modifier(NowPlayingInset()) }
}

struct NowPlayingBar: View {
    @EnvironmentObject private var playback: PlaybackController

    var body: some View {
        let state = playback.state
        HStack(spacing: 12) {
            LogoView(url: state.channel?.logoURL, isRadio: state.isAudioOnly)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: state.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let failure = state.failure {
                    Text(failure.message).font(.caption).foregroundStyle(.red).lineLimit(1)
                } else if let subtitle = state.subtitle {
                    Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: state.isPlaying || state.phase == .loading ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(state.isPlaying ? Text("Duraklat") : Text("Oynat"))
            Button {
                playback.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.body)
                    .frame(width: 36, height: 44)
            }
            .accessibilityLabel(Text("Durdur"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .contentShape(Rectangle())
        .onTapGesture { playback.isPlayerPresented = true }
    }
}
