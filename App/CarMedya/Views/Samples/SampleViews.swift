import CarMediaCore
import CarMediaKit
import SwiftUI

/// The bundled sample manifest (`SampleContent.json`), loaded once.
enum SampleLibrary {
    static let content: SampleContent = {
        guard let url = Bundle.main.url(forResource: "SampleContent", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let content = try? SampleContent.decode(data) else {
            return SampleContent(version: 1, collections: [])
        }
        return content
    }()

    /// Plays `item` with the rest of its collection as the queue.
    @MainActor
    static func play(_ item: SampleItem) {
        let collection = content.collections.first { $0.items.contains(item) }
        let queue = (collection?.items ?? [item]).map(\.channel)
        PlaybackController.shared.play(item.channel, queue: queue)
    }
}

/// Horizontal poster rows, one per sample collection.
struct SampleShelves: View {
    var body: some View {
        ForEach(SampleLibrary.content.collections) { collection in
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: collection.title).font(.headline)
                    Text(verbatim: collection.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(collection.items) { item in
                            NavigationLink(value: item) {
                                SamplePosterCell(item: item)
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

/// Grid of all samples (used when there is no Xtream account in "Filmler ve Diziler").
struct SampleGrid: View {
    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 12, alignment: .top)]

    var body: some View {
        ForEach(SampleLibrary.content.collections) { collection in
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: collection.title)
                    .font(.headline)
                    .padding(.horizontal)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(collection.items) { item in
                        NavigationLink(value: item) {
                            SamplePosterCell(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct SamplePosterCell: View {
    let item: SampleItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PosterView(url: item.posterURL, symbol: "film")
                .overlay(alignment: .topLeading) {
                    Text("Ücretsiz")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(4)
                }
            Text(verbatim: item.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(verbatim: String(item.year))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Poster, summary, license and play button of one sample.
struct SampleDetailView: View {
    let item: SampleItem
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    PosterView(url: item.posterURL)
                        .frame(width: 130)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: item.title)
                            .font(.title3.weight(.bold))
                        Text(verbatim: metadataLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label("Ücretsiz ve yasal", systemImage: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }

                Button {
                    SampleLibrary.play(item)
                } label: {
                    Label("Oynat", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text(verbatim: item.summary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Lisans")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(verbatim: item.attribution)
                        .font(.subheadline)
                    HStack(spacing: 16) {
                        if let url = item.licenseURL {
                            Button { openURL(url) } label: { Text(verbatim: item.license) }
                        } else {
                            Text(verbatim: item.license)
                        }
                        if let source = item.sourceURL {
                            Button { openURL(source) } label: { Text("Kaynak") }
                        }
                    }
                    .font(.subheadline)
                }
            }
            .padding()
        }
        .navigationTitle(Text(verbatim: item.title))
        .navigationBarTitleDisplayMode(.inline)
        .nowPlayingInset()
    }

    private var metadataLine: String {
        var parts = [String(item.year)]
        if let duration = item.duration, duration > 0 {
            parts.append(DurationText.short(seconds: duration))
        }
        return parts.joined(separator: " · ")
    }
}

/// Settings > "Lisanslar ve kaynaklar": credits for every bundled sample.
struct LicensesView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                Text("CarMedya kanal, liste veya yayın sağlamaz. Aşağıdaki örnek videolar, hak sahiplerinin serbest lisansıyla ve kendi sunucularından oynatılır.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(SampleLibrary.content.collections) { collection in
                Section {
                    ForEach(collection.items) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: "\(item.title) (\(item.year))")
                                .font(.subheadline.weight(.medium))
                            Text(verbatim: item.attribution)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let url = item.licenseURL {
                                Button { openURL(url) } label: { Text(verbatim: item.license).font(.caption) }
                                    .buttonStyle(.borderless)
                            } else {
                                Text(verbatim: item.license).font(.caption)
                            }
                        }
                    }
                } header: {
                    Text(verbatim: collection.title)
                }
            }
        }
        .navigationTitle("Lisanslar ve kaynaklar")
        .navigationBarTitleDisplayMode(.inline)
    }
}
