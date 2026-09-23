# CarPlay Medya

Kullanıcının **kendi** içeriğini (M3U listesi, Xtream Codes hesabı, XMLTV rehberi) telefonda ve CarPlay'de oynatan iOS uygulaması ve motoru. Uygulama içerik sağlamaz; depo hiçbir kanal listesi taşımaz.

Depo iki parçadan oluşur:
- **Swift paketi** (kök dizin): `CarMediaCore` (ayrıştırıcılar, Xtream, EPG) ve `CarMediaKit` (kaynak yönetimi, kütüphane durumu, oynatma kuralları). İkisi de yalnız Foundation kullanır; iOS 17+, macOS 14+ ve Windows'ta derlenir.
- **iOS uygulaması** (`App/`): SwiftUI telefon arayüzü + CarPlay ses sahnesi. Xcode projesi `App/project.yml`'den XcodeGen ile üretilir.

## İçerik
| Modül | Ne yapar |
|---|---|
| `M3U` | `M3UParser` (EXTINF öznitelikleri, EXTGRP, EXTVLCOPT, KODIPROP, CRLF/BOM, boşluklu URL), `PlaylistSniffer` ("bu adres kanal listesi değil, medya akışı" tespiti), `PlaylistLoader` |
| `Xtream` | `XtreamCredentials` (adres normalleştirme, parola gizleme), `XtreamEndpoints` (tüm `player_api.php` eylemleri ve akış URL'leri), toleranslı DTO'lar, `XtreamClient` |
| `EPG` | `XMLTVParser` (akışlı SAX), `EPGStore` (şimdi/sonraki, aralık sorgusu, `tvg-id` eşleme) |
| `Networking` | `HTTPTransport` protokolü, `URLSessionTransport` (zaman aşımı, User-Agent, yönlendirme politikası) |
| `Models` | `Channel`, `ChannelGroup`, `Playlist`, `MediaSource`, `StreamKind`, `MediaContainer`, `EPGChannel`, `Programme` |

`CarMediaKit`: `SourceStore`/`InMemorySourceStore` (kaynak ekle/sil/yenile, parolasız `Codable` anlık görüntü), `LibraryState` (gruplar, favoriler, son oynatılanlar, Türkçe duyarlı arama), `NowPlayingState`, `MotionPolicy` (8 km/sa üstü video kapanır, 3 km/sa altı açılır), `PlaybackURLResolver` (Xtream'de `.m3u8`; MKV/RTSP/UDP/ham TS için açık "desteklenmiyor"), `EPGPresenter` (şimdi/sonraki, ilerleme).

## Derleme ve test
```bash
swift build
swift test
```
Windows kurulumu ve ortam değişkenleri için `CLAUDE.md`'ye bakın.

## iOS uygulaması
```bash
brew install xcodegen
cd App && xcodegen generate
xcodebuild -project CarMedya.xcodeproj -scheme CarMedya   -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
Mac olmayan ortamda iOS derlemesi GitHub Actions'ta (`.github/workflows/app.yml`, macos-15) yapılır.

- **Sekmeler:** Kütüphane (gruplar → kanallar, logo, EPG şimdi/sonraki), Favoriler, Kaynaklar (M3U adresi, Xtream hesabı + bağlantı testi, dosyadan içe aktarma), Ayarlar.
- **Oynatıcı:** `AVPlayerViewController` (PiP, AirPlay video), `AVRoutePickerView`; araç hareket halindeyken video gizlenir, ses sürer.
- **CarPlay (ses):** Favoriler / Kanallar / Son Oynatılan sekmeleri, `CPNowPlayingTemplate`. CarPlay video (iOS 27) v1.1'de.
- **Entitlement:** `carplay-audio` ve `carplay-video` Apple'dan istendi, henüz verilmedi; CI imzasız derler.

### App Review notu: ATS (`NSAllowsArbitraryLoads`)
Uygulama, kullanıcının kendi girdiği adreslerden (kendi M3U listesi, Xtream sunucusu, ev medya sunucusu) oynatır. Bu sunucuların çoğu yalnız düz HTTP sunar ve alan adları önceden bilinemez; alan adı bazlı istisna mümkün değildir. Uygulama içerik taşımaz ve kullanıcının eklemediği hiçbir sunucuya bağlanmaz. (Gerekçe `App/Config/Info.plist` içinde de yorum olarak durur.)

## Kullanım örneği
```swift
let playlist = try await PlaylistLoader().load(from: listURL)
let client = XtreamClient(credentials: try XtreamCredentials(baseURL: "sunucu.example.com:8080",
                                                             username: "kullanici", password: parola))
let hesap = try await client.accountInfo()
let rehber = try XMLTVParser.parse(fileURL: rehberDosyasi).makeStore()
let simdi = rehber.current(for: rehber.resolveChannelID(for: kanal) ?? "", at: .now)
```
