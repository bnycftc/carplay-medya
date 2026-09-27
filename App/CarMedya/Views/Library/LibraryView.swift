import CarMediaCore
import CarMediaKit
import SwiftUI

/// "Canlı TV": group chips on top, channels right below — one tap from opening the tab to watching.
struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("library.selectedGroup") private var selectedGroupID = LibraryFilter.all
    @State private var query = ""
    @State private var editsGroups = false
    @State private var addsSource = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Canlı TV")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: Text("Kanal ara"))
                .refreshable { await model.refreshAll(force: true) }
                .sheet(isPresented: $editsGroups) { GroupsEditorView() }
                .sheet(isPresented: $addsSource) { QuickAddSourceView() }
                .toolbar {
                    if !model.library.isEmpty {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                editsGroups = true
                            } label: {
                                Label("Grupları düzenle", systemImage: "line.3.horizontal.decrease.circle")
                            }
                        }
                    }
                    if !model.guides.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink {
                                GuideView()
                            } label: {
                                Label("Rehber", systemImage: "calendar")
                            }
                        }
                    }
                }
                .nowPlayingInset()
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.library.isEmpty {
            if model.refreshingSourceIDs.isEmpty {
                ContentUnavailableView {
                    Label("Henüz kanal yok", systemImage: "tv")
                } description: {
                    Text("Sağlayıcının verdiği IPTV bağlantısını veya Xtream bilgilerini yapıştır; kanallar burada gruplarıyla görünür.")
                } actions: {
                    Button {
                        addsSource = true
                    } label: {
                        Label("Bağlantı yapıştır", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView("Kaynaklar yükleniyor…")
            }
        } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            let results = model.library.search(query)
            TimelineView(.everyMinute) { context in
                List {
                    if results.isEmpty {
                        Text("Sonuç bulunamadı").foregroundStyle(.secondary)
                    }
                    ChannelRows(channels: results, date: context.date)
                }
                .listStyle(.plain)
            }
        } else if model.library.visibleSections.isEmpty {
            ContentUnavailableView {
                Label("Tüm gruplar gizli", systemImage: "eye.slash")
            } description: {
                Text("Göstermek istediğiniz grupları açın. Arama gizli grupları da bulur.")
            } actions: {
                Button("Grupları düzenle") { editsGroups = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            let filters = LibraryFilter.available(in: model.library)
            let selection = filters.contains { $0.id == selectedGroupID } ? selectedGroupID : LibraryFilter.all
            let channels = LibraryFilter.channels(for: selection, in: model.library)
            TimelineView(.everyMinute) { context in
                List {
                    if channels.isEmpty {
                        Text("Bu grupta kanal yok").foregroundStyle(.secondary)
                    }
                    ChannelRows(channels: channels, date: context.date)
                }
                .listStyle(.plain)
                .safeAreaInset(edge: .top, spacing: 0) {
                    GroupChips(filters: filters, selection: selection) { selectedGroupID = $0 }
                        .background(.bar)
                }
            }
        }
    }
}

/// A chip in the Live TV filter bar: all channels, favorites, or one (visible) group.
struct LibraryFilter: Identifiable, Hashable {
    static let all = "__all__"
    static let favorites = "__favorites__"

    let id: String
    let title: String
    let count: Int

    /// "Tümü", "Favoriler" (if any), then visible groups in library order.
    static func available(in library: LibraryState) -> [LibraryFilter] {
        var filters = [LibraryFilter(id: all, title: String(localized: "Tümü"), count: library.visibleChannels.count)]
        let favorites = library.favorites
        if !favorites.isEmpty {
            filters.append(LibraryFilter(id: Self.favorites, title: String(localized: "Favoriler"), count: favorites.count))
        }
        let multipleSources = library.visibleSections.count > 1
        for section in library.visibleSections {
            for group in section.groups {
                let name = group.name ?? String(localized: "Diğer")
                let title = multipleSources && group.name == nil ? "\(section.title) · \(name)" : name
                filters.append(LibraryFilter(id: group.id, title: title, count: group.count))
            }
        }
        return filters
    }

    static func channels(for id: String, in library: LibraryState) -> [Channel] {
        switch id {
        case all: return library.visibleChannels
        case favorites: return library.favorites
        default: return library.group(id: id).map { library.channels(in: $0) } ?? []
        }
    }
}

/// Horizontally scrolling group filter that keeps the selected chip in view.
struct GroupChips: View {
    let filters: [LibraryFilter]
    let selection: String
    let select: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(filters) { filter in
                        let isSelected = filter.id == selection
                        Button {
                            select(filter.id)
                        } label: {
                            HStack(spacing: 4) {
                                if filter.id == LibraryFilter.favorites {
                                    Image(systemName: "star.fill").font(.caption2)
                                }
                                Text(verbatim: filter.title)
                                Text(verbatim: "\(filter.count)")
                                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemBackground)))
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .id(filter.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
        .frame(height: 48)
    }
}
