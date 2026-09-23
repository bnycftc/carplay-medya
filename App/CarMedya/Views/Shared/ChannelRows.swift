import CarMediaCore
import CarMediaKit
import SwiftUI

/// Rows for a list of channels: tap plays (with the list as the skip queue), swipe toggles favorite.
struct ChannelRows: View {
    let channels: [Channel]
    let date: Date
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackController

    var body: some View {
        ForEach(channels) { channel in
            let isFavorite = model.isFavorite(channel.id)
            Button {
                playback.play(channel, queue: channels)
            } label: {
                ChannelRow(
                    title: channel.title,
                    logoURL: channel.logoURL,
                    isRadio: channel.isRadio,
                    summary: model.epgSummary(for: channel, at: date),
                    isFavorite: isFavorite,
                    isCurrent: playback.state.channel?.id == channel.id
                )
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                favoriteButton(for: channel, isFavorite: isFavorite)
            }
            .contextMenu {
                favoriteButton(for: channel, isFavorite: isFavorite)
            }
        }
    }

    private func favoriteButton(for channel: Channel, isFavorite: Bool) -> some View {
        Button {
            model.toggleFavorite(channel.id)
        } label: {
            if isFavorite {
                Label("Favorilerden çıkar", systemImage: "star.slash")
            } else {
                Label("Favorilere ekle", systemImage: "star")
            }
        }
        .tint(.yellow)
    }
}
