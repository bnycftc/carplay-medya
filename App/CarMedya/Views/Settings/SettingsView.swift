import CarMediaKit
import CoreLocation
import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var motion: MotionMonitor
    @EnvironmentObject private var playback: PlaybackController
    @AppStorage(SettingsKeys.motionPolicyEnabled) private var motionPolicyEnabled = false
    @AppStorage(SettingsKeys.carVideoEnabled) private var carVideoEnabled = false
    @AppStorage(SettingsKeys.channelSkipEnabled) private var channelSkipEnabled = true
    @AppStorage(SettingsKeys.autoplayNextEpisode) private var autoplayNextEpisode = true
    @AppStorage(SettingsKeys.showSamples) private var showSamples = true
    @AppStorage(SettingsKeys.onboardingCompleted) private var onboardingCompleted = false
    @Environment(\.openURL) private var openURL
    @ObservedObject private var catalog = CatalogModel.shared
    @ObservedObject private var carVideo = CarVideoDiagnostics.shared
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
                    Text("Açıksa, GPS hızı 8 km/sa'i geçince telefonda video gizlenir ve yalnız ses devam eder; 3 km/sa'in altına inince video geri gelir. Hız bilinmiyorsa video gösterilir.")
                }

                carVideoSection

                Section {
                    Toggle("Kilit ekranında ve CarPlay'de kanal atlama", isOn: $channelSkipEnabled)
                        .onChange(of: channelSkipEnabled) { _, enabled in
                            playback.setChannelSkipEnabled(enabled)
                        }
                    Toggle("Bölüm bitince sonrakini oynat", isOn: $autoplayNextEpisode)
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
                    Toggle("Ana sayfada ücretsiz örnekleri göster", isOn: $showSamples)
                    NavigationLink {
                        LicensesView()
                    } label: {
                        Label("Lisanslar ve kaynaklar", systemImage: "doc.text")
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

    /// Video on the car display: the setting plus what the last CarPlay session reported.
    private var carVideoSection: some View {
        let diagnosis = CarVideoDiagnosis(snapshot: carVideo.snapshot, settingOn: carVideoEnabled)
        return Section {
            Toggle("Park halinde araç ekranında video", isOn: $carVideoEnabled)
                .accessibilityIdentifier("settings.carVideo.toggle")
            VStack(alignment: .leading, spacing: 4) {
                Label(diagnosis.title, systemImage: diagnosis.symbol)
                    .bold()
                    .accessibilityIdentifier("settings.carVideo.diagnosis")
                Text(diagnosis.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let snapshot = carVideo.snapshot {
                LabeledContent("Son bağlantı") {
                    Text(snapshot.connectedAt.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("iOS desteği") { yesNoText(snapshot.systemSupportsAPI) }
                LabeledContent("Araç video bildiriyor") { yesNoText(snapshot.carSupportsVideo) }
                LabeledContent("Ayar") { carVideoEnabled ? Text("Açık") : Text("Kapalı") }
                LabeledContent("Video satırı oynatıldı") { yesNoText(snapshot.playedVideoItem) }
                LabeledContent("Görüntü araç ekranına gitti") { yesNoText(snapshot.externalPlaybackSeen) }
            }
        } header: {
            Text("Araç ekranında video")
        } footer: {
            Text("Araç ekranında video yalnız bunu destekleyen araçlarda ve park halindeyken oynar; araç izin vermezse yalnız ses çalar. Durum satırları son CarPlay bağlantısından alınır.")
        }
    }

    private func yesNoText(_ value: Bool?) -> Text {
        guard let value else { return Text("Bilinmiyor") }
        return value ? Text("Evet") : Text("Hayır")
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
