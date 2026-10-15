# CarPlay Medya — proje kuralları

Plan ve gerekçeler: `carplay-medya-plani.md` (bu dosyayı değiştirme).

## Kırmızı çizgiler
- **Yalnız Apple'ın onayladığı yollar.** Ekran yansıtma, özel API, gri yöntem yok. CarPlay video yalnız resmi iOS 27 video kategorisi + AirPlay video üzerinden.
- **İçerik taşımıyoruz.** Uygulama ve paket hiçbir kanal listesi, gerçek yayın URL'si, gerçek sağlayıcı adresi, telifli isim/logo içermez. Test verileri kurmaca olur ve yalnız `example.com` alan adlarını kullanır.
  - **Tek istisna (bny kararı, 2026-09-27):** `App/CarMedya/Resources/SampleContent.json` içindeki örnek paket. Yalnız hak sahibinin kendi sunucusundan oynatılan, lisansı belgelenmiş videolar: Blender açık filmleri (CC BY / CC BY-SA, `video.blender.org`) ve NASA videoları (ABD kamu malı, `images-assets.nasa.gov`, üçüncü taraf müzik/görüntü kredisi olmayanlar). Canlı TV kanalı, IPTV listesi (iptv-org vb.), archive.org ya da radyo dizini **eklenmez**; gerekçe `docs/DURUM.md` ve BnyOS araştırma kayıtlarında. `CacheAndIndexTests` manifesti denetler (yalnız bu iki alan adı, https, lisans ve atıf dolu).
- **AVPlayer/HLS çekirdek.** Oynatma AVPlayer ile; Xtream'de `.m3u8` tercih edilir. MKV/RTSP/UDP/ham TS desteklenmez, kullanıcıya açıkça söylenir.
- **CarMediaCore ve CarMediaKit saf Swift'tir.** Yalnız Foundation; UIKit, AVFoundation, SwiftUI, CarPlay import edilmez. Windows'ta derlenip test edilebilir kalmalı. AVFoundation/CarPlay/UIKit/SwiftUI yalnız `App/` içinde.
- **Parola asla loglanmaz.** `XtreamCredentials` açıklamaları parolayı gizler; hata mesajları `Redaction` ile temizlenir. Parola Keychain'de (`AfterFirstUnlock`) tutulur, `MediaSource`/`XtreamAccount` parolasızdır. Xtream çalma listeleri (URL'lerde parola var) diske yazılmaz; açılışta yeniden çekilir. Kalıcı hata kaydı metin değil `UserFacingError` sınıfıdır.
- **Özel API yok, AVFoundation dahil.** Örn. `AVURLAssetHTTPHeaderFieldsKey` kullanılmaz; yalnız public `AVURLAssetHTTPUserAgentKey`.
- **Now Playing:** iOS 17–26 için `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` yalnız `NowPlayingInfoPublisher.swift` içinde. iOS 27 Now Playing framework'üne geçişte dosya bütünüyle değişir; ikisi aynı anda kullanılmaz.

## Yapı
- `Sources/CarMediaCore/` — Models, M3U, Xtream, EPG, Networking, Support
- `Sources/CarMediaKit/` — uygulama mantığı (Foundation): `SourceStore`/`InMemorySourceStore`, `DefaultPlaylistProvider`, `CredentialStore`, `SourceDraft`, `LibraryState`, `NowPlayingState`, `MotionPolicy`, `PlaybackURLResolver`, `EPGPresenter`, `ListCapping`, `UserFacingError`, `SnapshotFile`, `Browser/BrowserAddress` (tarayıcı girdisi → yalnız http(s) URL)
- `Tests/CarMediaCoreTests/` — XCTest; fikstürler `Fixtures/` altında (`Bundle.module`)
- `Tests/CarMediaKitTests/` — XCTest; sahte veriler satır içi, yalnız `example.com`
- `App/project.yml` — XcodeGen tanımı (iOS 17, Swift 5 modu, bundle `com.bnycftc.carmedya`, takım `26322AY3MH`); `App/CarMedya.xcodeproj` üretilir ve git'e girmez
- `App/Config/Info.plist` — sahne manifestosu (telefon + `CPTemplateApplicationSceneSessionRoleApplication`), `UIBackgroundModes: audio`, ATS gerekçesi yorum olarak
- `App/CarMedya/` — `App/` (giriş, AppDelegate), `Services/` (AppModel, PlaybackController, NowPlayingInfoPublisher, MotionMonitor, KeychainStore, ImageLoader), `Views/` (SwiftUI; `Views/Browser/` yalnız telefon tarayıcısı, `SFSafariViewController`), `CarPlay/` (CarPlaySceneDelegate), `Resources/` (xcstrings: tr kaynak, en çeviri; asset catalog)

## Mac yok: iOS derlemesi CI'da
- Bu makinede Xcode yok; iOS kodu yerelde derlenemez. `.github/workflows/app.yml` GitHub "xcode-27" runner'ında (Xcode 27.0, `DEVELOPER_DIR` ile sabit; iOS 27 SDK macos-15/26'da yok) `xcodegen generate` + `xcodebuild` (iOS Simulator, `CODE_SIGNING_ALLOWED=NO`) çalıştırır ve paket testlerini koşar. Hata olursa `xcodebuild-log` artifact'ine bak.
- Yerelde yapılabilecek kontrol: `swiftc -parse` ile sözdizimi (tip denetimi yok).
- iOS kodunu temkinli yaz: iOS 17 SDK API'leri, yeni API'ler `@available`/`#available` arkasında; emin olunmayan iOS 27 sembolü yazılmaz.
- Test edilebilir mantık `App/`'e değil `CarMediaKit`'e konur.
- `.github/workflows/ci.yml` paketleri macOS + Windows'ta test eder; `app.yml` iOS uygulamasını derler.
- `.github/workflows/testflight.yml` (elle `gh workflow run testflight.yml` veya `v*` etiketi): XcodeGen → `xcodebuild archive` (otomatik/bulut imzalama, `-allowProvisioningUpdates` + App Store Connect API anahtarı, `DEVELOPMENT_TEAM=26322AY3MH`, `CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER`) → `xcodebuild -exportArchive` + `App/ExportOptions.plist` (`app-store-connect`, `destination: upload`) ile TestFlight'a yükler. Sertifika/profil saklanmaz. Bu iş akışı da "xcode-27" runner'ında Xcode 27.0'ı `DEVELOPER_DIR` ile sabitler; yükleme için beta Xcode kullanma (App Store Connect betayla derlenmiş build'i reddeder). İmzalı entitlement'ların yalnız ses (`carplay-audio`) olduğunu doğrulayan bir adım vardır.
  - Secret'lar: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (ham çok satırlı `.p8` ya da base64'ü). Anahtar: App Store Connect → Users and Access → Integrations → Team Keys, rol **Admin** (App Manager bulut dağıtım imzasında `Cloud signing permission error` verir); `.p8` yalnız bir kez indirilir.
  - İlk yükleme için App Store Connect'te aynı bundle ID (`com.bnycftc.carmedya`) ile uygulama kaydı olmalı.
  - Sürüm `project.yml`'de `MARKETING_VERSION`; build numarasını elle artırma, iş akışı verir. Yükleme 1024×1024 alfasız ikon ister (`AppIcon.appiconset/AppIcon-1024.png`, şimdilik yer tutucu).
- **Entitlement durumu (karar 2026-10-15):** yalnız `com.apple.developer.carplay-audio` kullanılır (verildi 2026-09-24), `CarMedya.entitlements`'ta. `carplay-video` Apple tarafından verildi (2026-10-15, Case 22408601) ama **bilerek eklenmez**: Apple CarPlay Developer Guide (Ekim 2026, s.4–5) — ses kategorisi "ses ya da ses+video karışımı" oynatır, video uygulamaları videosuz araçlarda gizlenir, kategoriler tek uygulamada birleşmez, video sunan ses uygulaması AirPlay video desteklemelidir. Videosuz araçta (bny'nin Kia EV3'ü) video yetkili uygulama kaybolurdu. App ID'de yalnız "CarPlay Audio App" açık, "CarPlay Video" kutusu kapalı kalır; dosyaya `carplay-video` ekleme. Araç ekranında görüntü, sistemin sunduğu AirPlay video ile gelir; uygulama yalnız CarPlay şablonları + `CPPlaybackConfiguration` üstverisi verir.
  - **iOS 27 CarPlay sembolleri (Apple dokümanıyla doğrulandı, 2026-10-15):** `CPSessionConfiguration.supportsVideoPlayback`, `CPPlaybackConfiguration(preferredPresentation:playbackAction:elapsedTime:duration:)` (`.audio/.none/.video`; `.none/.pause/.play/.replay`; süre 0 = bilinmiyor/canlı), `CPPlayableItem.playbackConfiguration` (`@NSCopying`: değiştirmek için yeni nesne ata), `AVPlayer.isExternalPlaybackActive`. Hepsi `#available(iOS 27, *)` arkasında; dağıtım hedefi iOS 17 kalır. Listede olmayan sembol yazılmaz.
- Mac'te yerel çalışma: `brew install xcodegen; cd App; xcodegen generate; open CarMedya.xcodeproj`. CarPlay simülatörü entitlement onayı gelmeden çalışmaz.

## Windows'ta derleme/test
Swift 6.4 toolchain (winget `Swift.Toolchain`) + VS 2022 Build Tools gerekir. Yeni bir PowerShell'de:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
$env:SDKROOT = [Environment]::GetEnvironmentVariable('SDKROOT','User')
Set-Location "C:\Users\bny\Documents\CarPlay Medya"
swift build
swift test
```

Notlar:
- `wchar_t ... broken by a context change` uyarıları toolchain kaynaklıdır, yok sayılabilir.
- `.build\debug` sembolik bağlantı uyarısı Windows'ta Developer Mode kapalıyken çıkar; zararsız.
- Windows'ta `XMLParser` `FoundationXML`, `URLSession`/`URLRequest` `FoundationNetworking` modülündedir; yeni dosyalarda `#if canImport(...)` ile içe aktar.
- Windows'ta `URL(string:)` iOS'a göre çok yavaş; 50k'lık liste performans ölçümü gerçek cihazda yapılmalı.
