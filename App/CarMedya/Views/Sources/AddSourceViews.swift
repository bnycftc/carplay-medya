import CarMediaCore
import CarMediaKit
import SwiftUI

struct AddM3USourceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var userAgent = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Liste adresi", text: $address, prompt: Text(verbatim: "http://sunucu.example.com/liste.m3u"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Ad (isteğe bağlı)", text: $name)
                } footer: {
                    Text("Yalnızca kullanma hakkınız olan listeleri ekleyin.")
                }
                Section("Gelişmiş") {
                    TextField("User-Agent (isteğe bağlı)", text: $userAgent)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let errorMessage {
                    Section {
                        Text(verbatim: errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("M3U listesi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Ekle") { save() }
                            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await model.addM3U(name: name, urlText: address, userAgent: userAgent)
                dismiss()
            } catch SourceStoreError.duplicateSource {
                errorMessage = String(localized: "Bu liste zaten ekli.")
            } catch {
                errorMessage = UserFacingError.from(error).message
            }
            isSaving = false
        }
    }
}

struct AddXtreamSourceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var summary: XtreamAccountSummary?
    @State private var errorMessage: String?

    private var isComplete: Bool {
        !server.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Sunucu adresi", text: $server, prompt: Text(verbatim: "http://sunucu.example.com:8080"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Kullanıcı adı", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Parola", text: $password)
                        .textContentType(.password)
                    TextField("Ad (isteğe bağlı)", text: $name)
                } footer: {
                    Text("Parola yalnızca bu cihazın anahtar zincirinde saklanır.")
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Text("Bağlantıyı test et")
                            if isBusy {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!isComplete || isBusy)

                    if let summary {
                        AccountSummaryView(summary: summary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(verbatim: errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Xtream hesabı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") { save() }
                        .disabled(!isComplete || isBusy)
                }
            }
            .interactiveDismissDisabled(isBusy)
            .onChange(of: server) { _, _ in summary = nil }
            .onChange(of: username) { _, _ in summary = nil }
        }
    }

    private func credentials() -> XtreamCredentials? {
        do {
            return try SourceDraft.xtreamCredentials(server: server, username: username, password: password)
        } catch {
            errorMessage = UserFacingError.from(error).message
            return nil
        }
    }

    private func testConnection() {
        errorMessage = nil
        summary = nil
        guard let credentials = credentials() else { return }
        isBusy = true
        Task {
            do {
                summary = try await model.testXtream(credentials)
            } catch {
                errorMessage = UserFacingError.from(error).message
            }
            isBusy = false
        }
    }

    private func save() {
        errorMessage = nil
        guard let credentials = credentials() else { return }
        isBusy = true
        Task {
            do {
                try await model.addXtream(name: name, credentials: credentials)
                dismiss()
            } catch SourceStoreError.duplicateSource {
                errorMessage = String(localized: "Bu hesap zaten ekli.")
            } catch {
                errorMessage = UserFacingError.from(error).message
            }
            isBusy = false
        }
    }
}

private struct AccountSummaryView: View {
    let summary: XtreamAccountSummary

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Durum") {
                statusText.foregroundStyle(isHealthy(now) ? .green : .red)
            }
            LabeledContent("Bitiş") {
                if let expiry = summary.expiresAt {
                    Text(expiry, format: .dateTime.day().month().year())
                } else {
                    Text("Süresiz")
                }
            }
            if let days = summary.daysRemaining(at: now), !summary.isExpired(at: now) {
                LabeledContent("Kalan") { Text("\(days) gün") }
            }
            if let active = summary.activeConnections, let max = summary.maxConnections {
                LabeledContent("Bağlantı") { Text(verbatim: "\(active) / \(max)") }
            }
            if summary.isTrial {
                Text("Deneme hesabı").font(.caption).foregroundStyle(.secondary)
            }
            if !summary.supportsHLS {
                Text("Sunucu HLS (.m3u8) çıktısı sunmuyor; kanallar oynatılamayabilir.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if summary.isAtConnectionLimit {
                Text("Tüm bağlantılar kullanımda; yeni yayın reddedilebilir.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func isHealthy(_ now: Date) -> Bool {
        summary.status == .active && !summary.isExpired(at: now)
    }

    private var statusText: Text {
        switch summary.status {
        case .active: return Text("Aktif")
        case .expired: return Text("Süresi dolmuş")
        case .banned: return Text("Engellenmiş")
        case .disabled: return Text("Devre dışı")
        case .other(let text): return Text(verbatim: text)
        case .unknown: return Text("Bilinmiyor")
        }
    }
}

/// One field for everything a provider sends: an M3U address, a `get.php` link, or a message with
/// server / username / password lines. Shows what was recognized before adding it.
struct QuickAddSourceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var name = ""
    @State private var isBusy = false
    @State private var summary: XtreamAccountSummary?
    @State private var errorMessage: String?

    private var detected: DetectedSource? { SourceLinkParser.detect(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 110)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Sağlayıcınızın verdiği bağlantıyı veya mesajı buraya yapıştırın")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first {
                            text = first
                        }
                    }
                } footer: {
                    Text("M3U adresi, get.php bağlantısı veya \"sunucu / kullanıcı adı / şifre\" içeren mesaj olabilir. Yalnızca kullanma hakkınız olan kaynakları ekleyin.")
                }

                detectionSection

                Section {
                    TextField("Ad (isteğe bağlı)", text: $name)
                }

                if let errorMessage {
                    Section {
                        Text(verbatim: errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Bağlantı yapıştır")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isBusy {
                        ProgressView()
                    } else {
                        Button("Ekle") { save() }
                            .disabled(detected == nil)
                    }
                }
            }
            .interactiveDismissDisabled(isBusy)
            .onChange(of: text) { _, _ in
                summary = nil
                errorMessage = nil
            }
        }
    }

    @ViewBuilder
    private var detectionSection: some View {
        switch detected {
        case .xtream(let server, let username, _)?:
            Section {
                Label("Xtream hesabı algılandı", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                LabeledContent("Sunucu") { Text(verbatim: server).lineLimit(1).truncationMode(.middle) }
                LabeledContent("Kullanıcı") { Text(verbatim: username) }
                LabeledContent("Şifre") { Text(verbatim: "••••••") }
                Button {
                    testConnection()
                } label: {
                    Text("Bağlantıyı test et")
                }
                .disabled(isBusy)
                if let summary {
                    AccountSummaryView(summary: summary)
                }
            } footer: {
                Text("Canlı kanallarla birlikte filmler, diziler ve program rehberi de gelir.")
            }
        case .m3u(let url)?:
            Section {
                Label("M3U listesi algılandı", systemImage: "list.bullet.rectangle")
                    .foregroundStyle(.green)
                Text(verbatim: url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        case nil:
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    Label("Bağlantı veya hesap bilgisi bulunamadı", systemImage: "questionmark.circle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func testConnection() {
        guard case .xtream(let server, let username, let password)? = detected else { return }
        errorMessage = nil
        isBusy = true
        Task {
            do {
                let credentials = try SourceDraft.xtreamCredentials(server: server, username: username, password: password)
                summary = try await model.testXtream(credentials)
            } catch {
                errorMessage = UserFacingError.from(error).message
            }
            isBusy = false
        }
    }

    private func save() {
        guard let detected else { return }
        errorMessage = nil
        isBusy = true
        Task {
            do {
                switch detected {
                case .xtream(let server, let username, let password):
                    let credentials = try SourceDraft.xtreamCredentials(server: server, username: username, password: password)
                    try await model.addXtream(name: name, credentials: credentials)
                case .m3u(let url):
                    try await model.addM3U(name: name, urlText: url, userAgent: nil)
                }
                dismiss()
            } catch SourceStoreError.duplicateSource {
                errorMessage = String(localized: "Bu kaynak zaten ekli.")
            } catch {
                errorMessage = UserFacingError.from(error).message
            }
            isBusy = false
        }
    }
}
