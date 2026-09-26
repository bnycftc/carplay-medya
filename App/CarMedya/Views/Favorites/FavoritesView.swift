import CarMediaCore
import CarMediaKit
import SwiftUI

/// Favorites and recents, editable. Pushed from the home screen ("Tümü").
struct FavoritesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackController

    var body: some View {
        content
            .navigationTitle("Favoriler")
            .toolbar {
                if !model.library.favorites.isEmpty {
                    EditButton()
                }
            }
            .nowPlayingInset()
    }

    @ViewBuilder
    private var content: some View {
        let favorites = model.library.favorites
        let recents = model.library.recents
        if favorites.isEmpty && recents.isEmpty {
            ContentUnavailableView {
                Label("Favori yok", systemImage: "star")
            } description: {
                Text("Bir kanalı sola kaydırarak favorilere ekleyin. Favoriler CarPlay'de de görünür.")
            }
        } else {
            TimelineView(.everyMinute) { context in
                List {
                    if !favorites.isEmpty {
                        Section("Favoriler") {
                            ForEach(favorites) { channel in
                                Button {
                                    playback.play(channel, queue: favorites)
                                } label: {
                                    ChannelRow(
                                        title: channel.title,
                                        logoURL: channel.logoURL,
                                        isRadio: channel.isRadio,
                                        summary: model.epgSummary(for: channel, at: context.date),
                                        isFavorite: false,
                                        isCurrent: playback.state.channel?.id == channel.id
                                    )
                                }
                            }
                            .onMove { source, destination in
                                guard let first = source.first else { return }
                                model.moveFavorite(from: first, to: destination)
                            }
                            .onDelete { offsets in
                                for index in offsets where favorites.indices.contains(index) {
                                    model.toggleFavorite(favorites[index].id)
                                }
                            }
                        }
                    }
                    if !recents.isEmpty {
                        Section {
                            ChannelRows(channels: recents, date: context.date)
                        } header: {
                            HStack {
                                Text("Son oynatılanlar")
                                Spacer()
                                Button("Temizle") { model.clearRecents() }
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }
}
