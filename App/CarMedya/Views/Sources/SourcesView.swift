import CarMediaCore
import CarMediaKit
import SwiftUI
import UniformTypeIdentifiers

struct SourcesView: View {
    private enum Sheet: String, Identifiable {
        case m3u, xtream
        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @State private var sheet: Sheet?
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                if model.records.isEmpty {
                    ContentUnavailableView {
                        Label("Kaynak yok", systemImage: "antenna.radiowaves.left.and.right")
                    } description: {
                        Text("Uygulama içerik sağlamaz. Kendi M3U listenizi, Xtream hesabınızı veya bir dosyayı ekleyin.")
                    }
                }
                ForEach(model.records) { record in
                    SourceRow(record: record, isRefreshing: model.refreshingSourceIDs.contains(record.id))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await model.remove(sourceID: record.id) }
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                            Button {
                                Task { await model.refresh(sourceID: record.id) }
                            } label: {
                                Label("Yenile", systemImage: "arrow.clockwise")
                            }
                            .tint(.blue)
                        }
                }
                Section {
                    Text("Desteklenen: HLS (.m3u8), MP4/MOV, MP3/AAC. MKV, RTSP, UDP ve ham TS desteklenmez.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Kaynaklar")
            .refreshable { await model.refreshAll(force: true) }
            .toolbar {
                Menu {
                    Button { sheet = .m3u } label: { Label("M3U liste adresi", systemImage: "link") }
                    Button { sheet = .xtream } label: { Label("Xtream Codes hesabı", systemImage: "person.badge.key") }
                    Button { isImporting = true } label: { Label("Dosyadan içe aktar", systemImage: "folder") }
                } label: {
                    Label("Kaynak ekle", systemImage: "plus")
                }
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .m3u: AddM3USourceView()
                case .xtream: AddXtreamSourceView()
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.m3uPlaylist, .plainText, .audiovisualContent, .audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        do {
                            try await model.importFile(at: url)
                        } catch {
                            importError = UserFacingError.from(error).message
                        }
                    }
                case .failure(let error):
                    importError = UserFacingError.from(error).message
                }
            }
            .alert(
                Text("İçe aktarılamadı"),
                isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } }),
                actions: { Button("Tamam", role: .cancel) {} },
                message: { Text(verbatim: importError ?? "") }
            )
            .nowPlayingInset()
        }
    }
}

private struct SourceRow: View {
    let record: SourceRecord
    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(verbatim: record.source.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if isRefreshing {
                    ProgressView()
                }
            }
            HStack(spacing: 6) {
                Text(kindLabel)
                Text(verbatim: "·")
                Text("\(record.channelCount) kanal")
                if let date = record.lastRefreshedAt {
                    Text(verbatim: "·")
                    Text(date, style: .relative)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let error = record.lastError {
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch record.source {
        case .m3uURL: return "list.bullet.rectangle"
        case .xtream: return "person.badge.key"
        case .localFile: return "doc"
        }
    }

    private var kindLabel: LocalizedStringKey {
        switch record.source {
        case .m3uURL: return "M3U liste"
        case .xtream: return "Xtream hesabı"
        case .localFile: return "Dosya"
        }
    }
}
