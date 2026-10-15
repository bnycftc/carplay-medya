import CarMediaCore
import CarMediaKit
import SwiftUI

/// "Ana Sayfa": everything ready to watch, one tap away, plus one search box for the whole app.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackController
    @ObservedObject private var catalog = CatalogModel.shared
    @AppStorage(SettingsKeys.showSamples) private var showSamples = true
    @State private var query = ""
    @State private var addsSource = false
    @State private var showsBrowser = false

    private var firstXtream: SourceRecord? { catalog.xtreamRecords.first }
    private var hasOwnContent: Bool { !model.records.isEmpty }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Ana Sayfa")
                .navigationDestination(for: CatalogItem.self) { item in
                    switch item.kind {
                    case .movie: MovieDetailView(item: item)
                    case .series: SeriesDetailView(item: item)
                    }
                }
                .navigationDestination(for: SampleItem.self) { item in
                    SampleDetailView(item: item)
                }
                .searchable(text: $query, prompt: Text("Kanal, film, dizi ara"))
                .refreshable { await model.refreshAll(force: true) }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsBrowser = true
                        } label: {
                            Label("Tarayıcı", systemImage: "globe")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            addsSource = true
                        } label: {
                            Label("Kaynak ekle", systemImage: "plus")
                        }
                    }
                }
                .sheet(isPresented: $addsSource) { QuickAddSourceView() }
                .sheet(isPresented: $showsBrowser) { BrowserView() }
                .nowPlayingInset()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            HomeSearchResults(query: query)
        } else {
            TimelineView(.everyMinute) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !hasOwnContent {
                            WelcomeCard { addsSource = true }
                                .padding(.horizontal)
                        } else if !model.refreshingSourceIDs.isEmpty && model.library.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Kaynaklar yükleniyor…").foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                        if let channel = playback.state.channel, playback.state.isActive {
                            NowWatchingCard(channel: channel, state: playback.state)
                                .padding(.horizontal)
                        }
                        if !catalog.continueWatching.entries.isEmpty {
                            ContinueWatchingShelf()
                        }
                        channelShelf(
                            title: Text("Favori kanallar"),
                            channels: model.library.favorites,
                            date: context.date,
                            showsAll: true
                        )
                        channelShelf(
                            title: Text("Son izlenenler"),
                            channels: Array(model.library.recents.prefix(20)),
                            date: context.date,
                            showsAll: false
                        )
                        if let source = firstXtream {
                            newArrivals(source: source, kind: .movie, title: Text("Yeni filmler"))
                            newArrivals(source: source, kind: .series, title: Text("Yeni diziler"))
                        }
                        if model.library.favorites.isEmpty && !model.library.isEmpty {
                            Label("Canlı TV'de bir kanalı sola kaydırarak favorilere ekleyin; burada ve CarPlay'de görünür.",
                                  systemImage: "star")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        }
                        if showSamples || !hasOwnContent {
                            SampleShelves()
                        }
                    }
                    .padding(.vertical)
                }
            }
            .task(id: firstXtream?.id) {
                guard let id = firstXtream?.id else { return }
                await catalog.load(sourceID: id, kind: .movie)
                await catalog.load(sourceID: id, kind: .series)
            }
        }
    }

    @ViewBuilder
    private func channelShelf(title: Text, channels: [Channel], date: Date, showsAll: Bool) -> some View {
        if !channels.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    title.font(.headline)
                    Spacer()
                    if showsAll {
                        NavigationLink {
                            FavoritesView()
                        } label: {
                            Text("Tümü").font(.subheadline)
                        }
                    }
                }
                .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(channels) { channel in
                            Button {
                                playback.play(channel, queue: channels)
                            } label: {
                                ChannelCard(
                                    channel: channel,
                                    summary: model.epgSummary(for: channel, at: date),
                                    isCurrent: playback.state.channel?.id == channel.id
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    model.toggleFavorite(channel.id)
                                } label: {
                                    if model.isFavorite(channel.id) {
                                        Label("Favorilerden çıkar", systemImage: "star.slash")
                                    } else {
                                        Label("Favorilere ekle", systemImage: "star")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder
    private func newArrivals(source: SourceRecord, kind: CatalogKind, title: Text) -> some View {
        if case .loaded(let loaded) = catalog.state(sourceID: source.id, kind: kind), !loaded.isEmpty {
            let items = Array(loaded.items(sort: .recentlyAdded).prefix(15))
            VStack(alignment: .leading, spacing: 8) {
                title
                    .font(.headline)
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                PosterCell(item: item, progress: nil)
                                    .frame(width: 110)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

/// A channel tile: logo, name, current programme and progress.
struct ChannelCard: View {
    let channel: Channel
    let summary: EPGSummary?
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LogoView(url: channel.logoURL, isRadio: channel.isRadio)
                .frame(width: 150, height: 84)
                .overlay(alignment: .topTrailing) {
                    if isCurrent {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                            .padding(5)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(4)
                    }
                }
            Text(verbatim: channel.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let now = summary?.now {
                Text(verbatim: now.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: summary?.progress ?? 0)
                    .progressViewStyle(.linear)
            } else if let group = channel.groupTitle {
                Text(verbatim: group)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 150, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Large card for what is playing now; tap opens the player.
struct NowWatchingCard: View {
    let channel: Channel
    let state: NowPlayingState
    @EnvironmentObject private var playback: PlaybackController

    var body: some View {
        Button {
            playback.isPlayerPresented = true
        } label: {
            HStack(spacing: 14) {
                LogoView(url: channel.logoURL, isRadio: state.isAudioOnly)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Şimdi oynuyor")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(verbatim: state.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let subtitle = state.subtitle {
                        Text(verbatim: subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let progress = state.progress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
}


/// First-run card: what the app is and how to start.
struct WelcomeCard: View {
    let addSource: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("CarMedya'ya hoş geldin", systemImage: "play.tv.fill")
                .font(.title3.weight(.bold))
            Text("Kendi IPTV bağlantını, Xtream hesabını veya dosyanı ekle; kanalların, filmlerin ve dizilerin burada toplanır, arabada CarPlay'den dinlersin. Denemek için aşağıdaki ücretsiz filmlerden birini açabilirsin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: addSource) {
                Label("Bağlantı yapıştır", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(uiColor: .secondarySystemBackground)))
    }
}

/// One search for channels, movies, series and samples.
struct HomeSearchResults: View {
    let query: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackController
    @ObservedObject private var catalog = CatalogModel.shared

    var body: some View {
        let channels = model.library.search(query, limit: 30)
        let movies = loadedItems(.movie)
        let series = loadedItems(.series)
        let samples = SampleLibrary.content.search(query)
        TimelineView(.everyMinute) { context in
            List {
                if channels.isEmpty && movies.isEmpty && series.isEmpty && samples.isEmpty {
                    Text("Sonuç bulunamadı").foregroundStyle(.secondary)
                }
                if !channels.isEmpty {
                    Section("Kanallar") {
                        ChannelRows(channels: channels, date: context.date)
                    }
                }
                if !movies.isEmpty {
                    Section("Filmler") {
                        ForEach(movies) { item in catalogRow(item) }
                    }
                }
                if !series.isEmpty {
                    Section("Diziler") {
                        ForEach(series) { item in catalogRow(item) }
                    }
                }
                if !samples.isEmpty {
                    Section("Ücretsiz örnekler") {
                        ForEach(samples) { item in
                            NavigationLink(value: item) {
                                resultRow(title: item.title, detail: String(item.year), poster: item.posterURL, symbol: "film")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func loadedItems(_ kind: CatalogKind) -> [CatalogItem] {
        var result: [CatalogItem] = []
        for record in catalog.xtreamRecords {
            if case .loaded(let loaded) = catalog.state(sourceID: record.id, kind: kind) {
                result += loaded.items(query: query, sort: .name).prefix(20)
            }
        }
        return Array(result.prefix(20))
    }

    private func catalogRow(_ item: CatalogItem) -> some View {
        NavigationLink(value: item) {
            resultRow(title: item.title, detail: item.year ?? item.ratingText.map { "★ \($0)" },
                      poster: item.posterURL, symbol: item.kind == .movie ? "film" : "tv")
        }
    }

    private func resultRow(title: String, detail: String?, poster: URL?, symbol: String) -> some View {
        HStack(spacing: 12) {
            PosterView(url: poster, symbol: symbol)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).lineLimit(2)
                if let detail {
                    Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
