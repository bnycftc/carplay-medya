import CarMediaCore
import CarMediaKit
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var editsGroups = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Canlı TV")
                .navigationDestination(for: String.self) { groupID in
                    GroupChannelsView(groupID: groupID)
                }
                .searchable(text: $query, prompt: Text("Kanal ara"))
                .refreshable { await model.refreshAll(force: true) }
                .sheet(isPresented: $editsGroups) { GroupsEditorView() }
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
                    Text("Uygulama içerik sağlamaz. Kaynaklar sekmesinden kendi listenizi, hesabınızı veya dosyanızı ekleyin.")
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
            List {
                ForEach(model.library.visibleSections) { section in
                    Section {
                        ForEach(section.groups) { group in
                            NavigationLink(value: group.id) {
                                HStack {
                                    if let name = group.name {
                                        Text(verbatim: name)
                                    } else {
                                        Text("Diğer")
                                    }
                                    Spacer()
                                    Text(verbatim: "\(group.count)")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    } header: {
                        Text(verbatim: section.title)
                    }
                }
            }
        }
    }
}

struct GroupChannelsView: View {
    let groupID: String
    @EnvironmentObject private var model: AppModel
    @State private var query = ""

    var body: some View {
        let group = model.library.group(id: groupID)
        let all = group.map { model.library.channels(in: $0) } ?? []
        let channels = model.library.filter(all, query: query)
        TimelineView(.everyMinute) { context in
            List {
                ChannelRows(channels: channels, date: context.date)
            }
            .listStyle(.plain)
        }
        .navigationTitle(group?.name.map { Text(verbatim: $0) } ?? Text("Diğer"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Bu grupta ara"))
        .nowPlayingInset()
    }
}
