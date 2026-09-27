import CarMediaCore
import CarMediaKit
import SwiftUI
import UIKit

/// "Filmler ve Diziler" tab: movie and series catalogs of the user's Xtream accounts.
struct CatalogView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var catalog = CatalogModel.shared
    @AppStorage("catalog.sourceID") private var selectedSourceID = ""
    @State private var kind: CatalogKind = .movie
    @State private var categoryID: String?
    @State private var sort: CatalogSort = .recentlyAdded
    @State private var query = ""

    private var records: [SourceRecord] { catalog.xtreamRecords }

    private var source: SourceRecord? {
        records.first { $0.id == selectedSourceID } ?? records.first
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Filmler ve Diziler")
                .toolbar { toolbarContent }
                .navigationDestination(for: CatalogItem.self) { item in
                    switch item.kind {
                    case .movie: MovieDetailView(item: item)
                    case .series: SeriesDetailView(item: item)
                    }
                }
                .nowPlayingInset()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let source {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Tür", selection: $kind) {
                        Text("Filmler").tag(CatalogKind.movie)
                        Text("Diziler").tag(CatalogKind.series)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if !catalog.continueWatching.entries.isEmpty && query.isEmpty {
                        ContinueWatchingShelf()
                    }

                    catalogBody(for: source)
                }
                .padding(.vertical)
            }
            .searchable(text: $query, prompt: kind == .movie ? Text("Film ara") : Text("Dizi ara"))
            .refreshable { await catalog.load(sourceID: source.id, kind: kind, force: true) }
            .task(id: "\(source.id)|\(kind.rawValue)") {
                categoryID = nil
                await catalog.load(sourceID: source.id, kind: kind)
            }
        } else {
            ContentUnavailableView {
                Label("Film ve dizi yok", systemImage: "film.stack")
            } description: {
                Text("Filmler ve diziler Xtream hesaplarından gelir. Kaynaklar sekmesinden kendi hesabınızı ekleyin.")
            }
        }
    }

    @ViewBuilder
    private func catalogBody(for source: SourceRecord) -> some View {
        switch catalog.state(sourceID: source.id, kind: kind) {
        case .idle, .loading:
            ProgressView(kind == .movie ? "Filmler yükleniyor…" : "Diziler yükleniyor…")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .failed(let error):
            VStack(spacing: 12) {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Yeniden dene") {
                    Task { await catalog.load(sourceID: source.id, kind: kind, force: true) }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding()
        case .loaded(let loaded):
            if loaded.isEmpty {
                Text(kind == .movie ? "Bu hesapta film yok." : "Bu hesapta dizi yok.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                if catalog.refreshingKeys.contains(CatalogModel.Key(sourceID: source.id, kind: kind)) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Güncelleniyor…")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                }
                if !loaded.categories.isEmpty {
                    CategoryChips(categories: loaded.categories, selection: $categoryID)
                }
                let items = loaded.items(categoryID: categoryID, query: query, sort: sort)
                if items.isEmpty {
                    Text("Sonuç bulunamadı")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    PosterGrid(items: items)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sırala", selection: $sort) {
                    Label("En yeni", systemImage: "clock").tag(CatalogSort.recentlyAdded)
                    Label("Ada göre", systemImage: "textformat").tag(CatalogSort.name)
                    Label("Puana göre", systemImage: "star").tag(CatalogSort.rating)
                }
                if records.count > 1 {
                    Picker("Hesap", selection: Binding(
                        get: { source?.id ?? "" },
                        set: { selectedSourceID = $0 }
                    )) {
                        ForEach(records) { record in
                            Text(verbatim: record.source.name).tag(record.id)
                        }
                    }
                }
            } label: {
                Label("Seçenekler", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }
}

/// Horizontally scrolling category filter.
struct CategoryChips: View {
    let categories: [CatalogCategory]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                chip(title: Text("Tümü"), isSelected: selection == nil) { selection = nil }
                ForEach(categories) { category in
                    chip(title: Text(verbatim: category.name), isSelected: selection == category.id) {
                        selection = category.id
                    }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 36)
    }

    private func chip(title: Text, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// Poster grid of catalog items.
struct PosterGrid: View {
    let items: [CatalogItem]
    @ObservedObject private var catalog = CatalogModel.shared

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 12, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    PosterCell(item: item, progress: progress(for: item))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private func progress(for item: CatalogItem) -> Double? {
        guard item.kind == .movie else { return nil }
        return catalog.continueWatching.progress(for: catalog.movieTarget(item).playableID)?.fraction
    }
}

struct PosterCell: View {
    let item: CatalogItem
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PosterView(url: item.posterURL, symbol: item.kind == .movie ? "film" : "tv")
                .overlay(alignment: .topTrailing) {
                    if let rating = item.ratingText {
                        Label(rating, systemImage: "star.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(4)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let progress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .padding(6)
                    }
                }
            Text(verbatim: item.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let year = item.year {
                Text(verbatim: year)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A 2:3 poster loaded through ``ImageLoader``.
struct PosterView: View {
    let url: URL?
    var symbol = "film"
    @State private var image: UIImage?

    var body: some View {
        Color(uiColor: .secondarySystemBackground)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
            .task(id: url) {
                guard let url else {
                    image = nil
                    return
                }
                image = ImageLoader.shared.cachedImage(for: url)
                if image == nil {
                    image = await ImageLoader.shared.image(for: url, maxPixelSize: 240)
                }
            }
    }
}

/// "İzlemeye devam" shelf: most recent unfinished movies and episodes.
struct ContinueWatchingShelf: View {
    @ObservedObject private var catalog = CatalogModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("İzlemeye devam")
                .font(.headline)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(catalog.continueWatching.entries) { entry in
                        Button {
                            catalog.play(entry.target, resume: true)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                PosterView(url: entry.target.posterURL,
                                           symbol: entry.target.kind == .movie ? "film" : "tv")
                                    .overlay(alignment: .bottom) {
                                        ProgressView(value: entry.fraction)
                                            .progressViewStyle(.linear)
                                            .padding(6)
                                    }
                                Text(verbatim: entry.target.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                if let subtitle = entry.target.subtitle {
                                    Text(verbatim: subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text("\(entry.minutesRemaining) dk kaldı")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 110)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                catalog.removeProgress(id: entry.id)
                            } label: {
                                Label("Listeden kaldır", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
