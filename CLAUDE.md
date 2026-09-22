# CarPlay Medya — proje kuralları

Plan ve gerekçeler: `carplay-medya-plani.md` (bu dosyayı değiştirme).

## Kırmızı çizgiler
- **Yalnız Apple'ın onayladığı yollar.** Ekran yansıtma, özel API, gri yöntem yok. CarPlay video yalnız resmi iOS 27 video kategorisi + AirPlay video üzerinden.
- **İçerik taşımıyoruz.** Uygulama ve paket hiçbir kanal listesi, gerçek yayın URL'si, gerçek sağlayıcı adresi, telifli isim/logo içermez. Test verileri kurmaca olur ve yalnız `example.com` alan adlarını kullanır.
- **AVPlayer/HLS çekirdek.** Oynatma AVPlayer ile; Xtream'de `.m3u8` tercih edilir. MKV/RTSP/UDP/ham TS desteklenmez, kullanıcıya açıkça söylenir.
- **CarMediaCore saf Swift'tir.** Yalnız Foundation; UIKit, AVFoundation, SwiftUI, CarPlay import edilmez. Windows'ta derlenip test edilebilir kalmalı.
- **Parola asla loglanmaz.** `XtreamCredentials` açıklamaları parolayı gizler; hata mesajları `Redaction` ile temizlenir. Parola Keychain'de (`AfterFirstUnlock`) tutulur, `MediaSource`/`XtreamAccount` parolasızdır.

## Yapı
- `Sources/CarMediaCore/` — Models, M3U, Xtream, EPG, Networking, Support
- `Tests/CarMediaCoreTests/` — XCTest; fikstürler `Fixtures/` altında (`Bundle.module`)

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
