import CarMediaCore
import CarMediaKit
import SwiftUI

/// Movie details: poster, metadata, plot and play / resume.
struct MovieDetailView: View {
    let item: CatalogItem
    @ObservedObject private var catalog = CatalogModel.shared
    @State private var details: XtreamVODDetails?
    @State private var containerOverride: String?
    @State private var isLoading = true
    @State private var unsupported: UnsupportedReason?

    private var target: WatchTarget {
        var target = catalog.movieTarget(item)
        if let containerOverride { target.containerExtension = containerOverride }
        if target.poster == nil { target.poster = details?.movieImage }
        return target
    }

    var body: some View {
        let target = self.target
        let progress = catalog.continueWatching.progress(for: target.playableID)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    PosterView(url: target.posterURL)
                        .frame(width: 130)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: details?.name.flatMap(nonEmpty) ?? item.title)
                            .font(.title3.weight(.bold))
                        if let line = metadataLine {
                            Text(verbatim: line)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let rating = item.ratingText {
                            Label(rating, systemImage: "star.fill")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                        if catalog.continueWatching.isWatched(target.playableID) {
                            Label("İzlendi", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    }
                }

                if let reason = unsupported {
                    Label(reason.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else {
                    PlayButtons(progress: progress) { resume in
                        catalog.play(target, resume: resume)
                    }
                }

                if let plot = details?.plot.flatMap(nonEmpty) {
                    Text(verbatim: plot)
                        .font(.body)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
                if let director = details?.director.flatMap(nonEmpty) {
                    DetailLine(title: Text("Yönetmen"), value: director)
                }
                if let cast = details?.cast.flatMap(nonEmpty) {
                    DetailLine(title: Text("Oyuncular"), value: cast)
                }
            }
            .padding()
        }
        .navigationTitle(Text(verbatim: item.title))
        .navigationBarTitleDisplayMode(.inline)
        .nowPlayingInset()
        .task(id: item.id) {
            defer { isLoading = false }
            guard let info = try? await catalog.vodInfo(for: item) else { return }
            details = info.info
            if let ext = info.movieData?.containerExtension.flatMap(nonEmpty) {
                containerOverride = ext
            }
        }
        .task(id: target.containerExtension) {
            unsupported = catalog.unsupportedReason(for: target)
        }
    }

    private var metadataLine: String? {
        var parts: [String] = []
        if let release = details?.releaseDate.flatMap(nonEmpty), let year = VODCatalog.year(fromReleaseDate: release) {
            parts.append(year)
        }
        if let genre = details?.genre.flatMap(nonEmpty) { parts.append(genre) }
        if let seconds = details?.durationSecs, seconds > 0 {
            parts.append(DurationText.short(seconds: Double(seconds)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Series details: seasons and episodes with progress.
struct SeriesDetailView: View {
    let item: CatalogItem
    @ObservedObject private var catalog = CatalogModel.shared
    @State private var info: XtreamSeriesInfo?
    @State private var failure: UserFacingError?
    @State private var season: String?
    @State private var resumeCandidate: XtreamEpisode?

    private var seasonKeys: [String] {
        (info?.episodes.keys.map { $0 } ?? []).sorted { (Int($0) ?? .max, $0) < (Int($1) ?? .max, $1) }
    }

    private var episodes: [XtreamEpisode] {
        guard let info, let season = season ?? seasonKeys.first else { return [] }
        return (info.episodes[season] ?? []).sorted { ($0.episodeNum ?? .max) < ($1.episodeNum ?? .max) }
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    PosterView(url: item.posterURL, symbol: "tv")
                        .frame(width: 100)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: item.title)
                            .font(.title3.weight(.bold))
                        if let line = metadataLine {
                            Text(verbatim: line)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let rating = item.ratingText {
                            Label(rating, systemImage: "star.fill")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                if let plot = info?.info?.plot.flatMap(nonEmpty) {
                    Text(verbatim: plot)
                        .font(.callout)
                }
            }

            if let failure {
                Section {
                    Label(failure.message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            } else if info == nil {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } else if seasonKeys.isEmpty {
                Section {
                    Text("Bu dizide bölüm yok.")
                        .foregroundStyle(.secondary)
                }
            } else {
                if seasonKeys.count > 1 {
                    Section {
                        Picker("Sezon", selection: Binding(
                            get: { season ?? seasonKeys.first ?? "" },
                            set: { season = $0 }
                        )) {
                            ForEach(seasonKeys, id: \.self) { key in
                                Text("Sezon \(key)").tag(key)
                            }
                        }
                    }
                }
                Section {
                    ForEach(episodes) { episode in
                        episodeButton(episode)
                    }
                } header: {
                    Text("Bölümler")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(verbatim: item.title))
        .navigationBarTitleDisplayMode(.inline)
        .nowPlayingInset()
        .confirmationDialog(
            "Kaldığınız yerden devam edilsin mi?",
            isPresented: Binding(get: { resumeCandidate != nil }, set: { if !$0 { resumeCandidate = nil } }),
            titleVisibility: .visible,
            presenting: resumeCandidate
        ) { episode in
            Button("Devam et") { play(episode, resume: true) }
            Button("Baştan başlat") { play(episode, resume: false) }
            Button("Vazgeç", role: .cancel) {}
        }
        .task(id: item.id) {
            do {
                info = try await catalog.seriesInfo(for: item)
                failure = nil
            } catch {
                failure = UserFacingError.from(error)
            }
        }
    }

    private func episodeButton(_ episode: XtreamEpisode) -> some View {
        let target = catalog.episodeTarget(episode, series: item)
        let progress = catalog.continueWatching.progress(for: target.playableID)
        let watched = catalog.continueWatching.isWatched(target.playableID)
        let unsupported = Self.isUnsupportedContainer(episode.containerExtension)
        return Button {
            if progress != nil {
                resumeCandidate = episode
            } else {
                play(episode, resume: false)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: CatalogModel.episodeLine(episode))
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if let seconds = episode.info?.durationSecs, seconds > 0 {
                            Text(verbatim: DurationText.short(seconds: Double(seconds)))
                        }
                        if unsupported {
                            Text("Desteklenmeyen biçim")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let progress {
                        ProgressView(value: progress.fraction)
                            .progressViewStyle(.linear)
                    }
                }
                Spacer(minLength: 0)
                if watched {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel(Text("İzlendi"))
                } else {
                    Image(systemName: "play.circle")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func play(_ episode: XtreamEpisode, resume: Bool) {
        let target = catalog.episodeTarget(episode, series: item)
        let queue = episodes.map { catalog.episodeTarget($0, series: item) }
        catalog.play(target, resume: resume, queue: queue)
    }

    private var metadataLine: String? {
        var parts: [String] = []
        if let year = item.year { parts.append(year) }
        if let genre = info?.info?.genre.flatMap(nonEmpty) { parts.append(genre) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func isUnsupportedContainer(_ ext: String?) -> Bool {
        ["mkv", "avi", "wmv", "flv", "webm", "ts"].contains(ext?.lowercased() ?? "")
    }
}

/// Play / resume buttons for on-demand items.
struct PlayButtons: View {
    let progress: WatchProgress?
    let action: (_ resume: Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let progress {
                Button {
                    action(true)
                } label: {
                    Label("Devam et (\(DurationText.clock(seconds: progress.position)))", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    action(false)
                } label: {
                    Label("Baştan", systemImage: "backward.end.fill")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    action(false)
                } label: {
                    Label("Oynat", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
    }
}

struct DetailLine: View {
    let title: Text
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.subheadline)
        }
    }
}

/// Duration formatting for on-demand items.
enum DurationText {
    /// "1 sa 32 dk" style, localized by the system.
    static func short(seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// "12:34" or "1:02:03".
    static func clock(seconds: Double) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(seconds).formatted(.time(pattern: pattern))
    }
}

private func nonEmpty(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
