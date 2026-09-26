import CoreLocation
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var motion: MotionMonitor
    @EnvironmentObject private var playback: PlaybackController
    @AppStorage(SettingsKeys.motionPolicyEnabled) private var motionPolicyEnabled = true
    @AppStorage(SettingsKeys.channelSkipEnabled) private var channelSkipEnabled = true
    @AppStorage(SettingsKeys.onboardingCompleted) private var onboardingCompleted = false
    @Environment(\.openURL) private var openURL
    @ObservedObject private var catalog = CatalogModel.shared
    @State private var confirmClearHistory = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Araç hareket halindeyken videoyu gizle", isOn: $motionPolicyEnabled)
                        .onChange(of: motionPolicyEnabled) { _, enabled in
                            motion.setEnabled(enabled)
                        }
                    if motionPolicyEnabled {
                        locationRow
                    }
                } header: {
                    Text("Sürüş güvenliği")
                } footer: {
                    Text("Hız 8 km/sa'i geçince telefonda video gizlenir ve yalnız ses devam eder; 3 km/sa'in altına inince video geri gelir. CarPlay ekranında video hiçbir zaman gösterilmez.")
                }

                Section {
                    Toggle("Kilit ekranında ve CarPlay'de kanal atlama", isOn: $channelSkipEnabled)
                        .onChange(of: channelSkipEnabled) { _, enabled in
                            playback.setChannelSkipEnabled(enabled)
                        }
                } header: {
                    Text("Oynatma")
                } footer: {
                    Text("İleri/geri tuşları, kanalın açıldığı listedeki sonraki veya önceki kanala geçer.")
                }

                Section {
                    Button(role: .destructive) {
                        confirmClearHistory = true
                    } label: {
                        Label("İzleme geçmişini temizle", systemImage: "trash")
                    }
                    .disabled(catalog.continueWatching.entries.isEmpty && catalog.continueWatching.watchedIDs.isEmpty)
                } footer: {
                    Text("Film ve bölümlerde kaldığınız yerler ile izlendi işaretleri yalnızca bu cihazda tutulur.")
                }

                Section {
                    Label {
                        Text("İçerik sağlamıyoruz. Uygulama kanal, liste veya yayın içermez, barındırmaz ve önermez. Yalnızca kendi eklediğiniz ve kullanma hakkınız olan kaynakları oynatır.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                    Link(destination: AppLinks.privacyPolicy) {
                        Label("Gizlilik politikası", systemImage: "hand.raised")
                    }
                    Link(destination: AppLinks.support) {
                        Label("Destek", systemImage: "questionmark.circle")
                    }
                    Button {
                        onboardingCompleted = false
                    } label: {
                        Label("Tanıtımı yeniden göster", systemImage: "sparkles")
                    }
                } header: {
                    Text("Hakkında")
                } footer: {
                    Text("Veri toplanmaz. Kaynak adresleri ve parolalar yalnızca bu cihazda saklanır.")
                }
            }
            .navigationTitle("Ayarlar")
            .confirmationDialog("İzleme geçmişi silinsin mi?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
                Button("Geçmişi temizle", role: .destructive) { catalog.clearHistory() }
                Button("Vazgeç", role: .cancel) {}
            }
            .nowPlayingInset()
        }
    }

    @ViewBuilder
    private var locationRow: some View {
        switch motion.authorization {
        case .notDetermined:
            Button("Hız algılama için konum izni ver") {
                motion.requestAuthorization()
            }
        case .denied, .restricted:
            Button("Konum izni kapalı — Ayarlar'ı aç") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        default:
            Label("Hız algılama açık", systemImage: "location.fill")
                .foregroundStyle(.secondary)
        }
    }
}
