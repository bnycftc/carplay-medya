import SwiftUI

/// First-launch introduction: no content provided / add your own source / no video while driving.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private struct Page {
        let symbol: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey
    }

    private let pages: [Page] = [
        Page(
            symbol: "tray",
            title: "İçerik sağlamıyoruz",
            text: "CarMedya boş gelir. Uygulama hiçbir kanal, liste veya yayın içermez ve önermez."
        ),
        Page(
            symbol: "plus.rectangle.on.folder",
            title: "Kendi kaynağınızı ekleyin",
            text: "Kullanma hakkınız olan M3U listenizi, Xtream hesabınızı veya bir dosyayı ekleyin. Parolalar yalnızca bu cihazda saklanır."
        ),
        Page(
            symbol: "car",
            title: "Sürerken video yok",
            text: "Araç hareket halindeyken video gösterilmez, yalnız ses çalar. CarPlay'de kanallar sesli oynatılır."
        ),
    ]

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    let item = pages[index]
                    VStack(spacing: 20) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 64, weight: .regular))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                        Text(item.title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text(item.text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Group {
                    if page < pages.count - 1 {
                        Text("Devam")
                    } else {
                        Text("Başla")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .interactiveDismissDisabled()
    }
}
