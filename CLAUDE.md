# CarPlay Medya — proje kuralları

Plan ve gerekçeler: `carplay-medya-plani.md` (bu dosyayı değiştirme).

## Kırmızı çizgiler
- **Yalnız Apple'ın onayladığı yollar.** Ekran yansıtma, özel API, gri yöntem yok. CarPlay video yalnız resmi iOS 27 video kategorisi + AirPlay video üzerinden.
- **İçerik taşımıyoruz.** Uygulama ve paket hiçbir kanal listesi, gerçek yayın URL'si, gerçek sağlayıcı adresi, telifli isim/logo içermez. Test verileri kurmaca olur ve yalnız `example.com` alan adlarını kullanır.
- **AVPlayer/HLS çekirdek.** Oynatma AVPlayer ile; Xtream'de `.m3u8` tercih edilir. MKV/RTSP/UDP/ham TS desteklenmez, kullanıcıya açıkça söylenir.
- **CarMediaCore ve CarMediaKit saf Swift'tir.** Yalnız Foundation; UIKit, AVFoundation, SwiftUI, CarPlay import edilmez. Windows'ta derlenip test edilebilir kalmalı. AVFoundation/CarPlay/UIKit/SwiftUI yalnız `App/` içinde.
- **Parola asla loglanmaz.** `XtreamCredentials` açıklamaları parolayı gizler; hata mesajları `Redaction` ile temizlenir. Parola Keychain'de (`AfterFirstUnlock`) tutulur, `MediaSource`/`XtreamAccount` parolasızdır. Xtream çalma listeleri (URL'lerde parola var) diske yazılmaz; açılışta yeniden çekilir. Kalıcı hata kaydı metin değil `UserFacingError` sınıfıdır.
- **Özel API yok, AVFoundation dahil.** Örn. `AVURLAssetHTTPHeaderFieldsKey` kullanılmaz; yalnız public `AVURLAssetHTTPUserAgentKey`.
- **Now Playing:** iOS 17–26 için `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` yalnız `NowPlayingInfoPublisher.swift` içinde. iOS 27 Now Playing framework'üne geçişte dosya bütünüyle değişir; ikisi aynı anda kullanılmaz.

## Yapı
- `Sources/CarMediaCore/` — Models, M3U, Xtream, EPG, Networking, Support
- `Sources/CarMediaKit/` — uygulama mantığı (Foundation): `SourceStore`/`InMemorySourceStore`, `DefaultPlaylistProvider`, `CredentialStore`, `SourceDraft`, `LibraryState`, `NowPlayingState`, `MotionPolicy`, `PlaybackURLResolver`, `EPGPresenter`, `ListCapping`, `UserFacingError`, `SnapshotFile`
- `Tests/CarMediaCoreTests/` — XCTest; fikstürler `Fixtures/` altında (`Bundle.module`)
- `Tests/CarMediaKitTests/` — XCTest; sahte veriler satır içi, yalnız `example.com`
- `App/project.yml` — XcodeGen tanımı (iOS 17, Swift 5 modu, bundle `com.bnycftc.carmedya`, takım `26322AY3MH`); `App/CarMedya.xcodeproj` üretilir ve git'e girmez
- `App/Config/Info.plist` — sahne manifestosu (telefon + `CPTemplateApplicationSceneSessionRoleApplication`), `UIBackgroundModes: audio`, ATS gerekçesi yorum olarak
- `App/CarMedya/` — `App/` (giriş, AppDelegate), `Services/` (AppModel, PlaybackController, NowPlayingInfoPublisher, MotionMonitor, KeychainStore, ImageLoader), `Views/` (SwiftUI), `CarPlay/` (CarPlaySceneDelegate), `Resources/` (xcstrings: tr kaynak, en çeviri; asset catalog)

## Mac yok: iOS derlemesi CI'da
- Bu makinede Xcode yok; iOS kodu yerelde derlenemez. `.github/workflows/app.yml` macos-15'te `xcodegen generate` + `xcodebuild` (iOS Simulator, `CODE_SIGNING_ALLOWED=NO`) çalıştırır ve paket testlerini koşar. Hata olursa `xcodebuild-log` artifact'ine bak.
- Yerelde yapılabilecek kontrol: `swiftc -parse` ile sözdizimi (tip denetimi yok).
- iOS kodunu temkinli yaz: iOS 17 SDK API'leri, yeni API'ler `@available`/`#available` arkasında; emin olunmayan iOS 27 sembolü yazılmaz.
- Test edilebilir mantık `App/`'e değil `CarMediaKit`'e konur.
- `.github/workflows/ci.yml` paketleri macOS + Windows'ta test eder; `app.yml` iOS uygulamasını derler. TestFlight henüz yok.
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
