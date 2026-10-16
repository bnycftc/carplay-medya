import CarMediaKit
import SafariServices
import SwiftUI

/// Phone-only web browser: an address or a search opens in a Safari view on the phone.
/// CarPlay shows templates only, so web pages never reach the car screen.
struct BrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var page: BrowserPage?

    /// Plain search URL used when the input is not an address; "%@" is the encoded query.
    private static let searchTemplate = "https://www.google.com/search?q=%@"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Adres yazın veya arayın", text: $input)
                            .keyboardType(.webSearch)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit { open() }
                            .accessibilityIdentifier("browser.address")
                        Button("Git") { open() }
                            .buttonStyle(.borderless)
                            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } footer: {
                    Text("Sayfalar telefonda Safari görünümünde açılır. CarPlay ekranında web sayfası gösterilmez.")
                }
            }
            .navigationTitle("Tarayıcı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .fullScreenCover(item: $page) { page in
                SafariView(url: page.url) { self.page = nil }
                    .ignoresSafeArea()
            }
        }
    }

    private func open() {
        guard let url = BrowserAddress.url(for: input, searchTemplate: Self.searchTemplate) else { return }
        page = BrowserPage(url: url)
    }
}

/// One page to show; a new id each time so the same address can be opened again.
struct BrowserPage: Identifiable {
    let id = UUID()
    let url: URL
}

/// `SFSafariViewController` for SwiftUI. Its Done button reports back so the cover's state is cleared.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onFinish()
        }
    }
}
