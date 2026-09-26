import CarMediaCore
import CarMediaKit
import SwiftUI

/// Show or hide channel groups. Hidden groups disappear from Live TV and CarPlay; search still finds them.
struct GroupsEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.library.sections) { section in
                    let groups = filtered(section.groups)
                    if !groups.isEmpty {
                        Section {
                            ForEach(groups) { group in
                                Toggle(isOn: Binding(
                                    get: { !model.library.isGroupHidden(group.id) },
                                    set: { model.setGroup(group.id, hidden: !$0) }
                                )) {
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
                            HStack {
                                Text(verbatim: section.title)
                                Spacer()
                                Menu {
                                    Button("Tümünü göster") { model.setAllGroups(ofSource: section.id, hidden: false) }
                                    Button("Tümünü gizle") { model.setAllGroups(ofSource: section.id, hidden: true) }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .textCase(nil)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: Text("Grup ara"))
            .navigationTitle("Grupları düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }

    private func filtered(_ groups: [LibraryGroup]) -> [LibraryGroup] {
        let tokens = SearchNormalizer.tokens(query)
        guard !tokens.isEmpty else { return groups }
        return groups.filter { SearchNormalizer.matches(normalizedKey: SearchNormalizer.normalize($0.name ?? ""), tokens: tokens) }
    }
}
