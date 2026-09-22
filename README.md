# CarPlay Medya — CarMediaCore

Kullanıcının **kendi** içeriğini (M3U listesi, Xtream Codes hesabı, XMLTV rehberi) telefonda ve CarPlay'de oynatacak iOS uygulamasının motoru. Uygulama içerik sağlamaz; bu paket de hiçbir kanal listesi taşımaz.

`CarMediaCore` saf Swift paketidir (yalnız Foundation). iOS 17+, macOS 14+ ve Windows'ta derlenir.

## İçerik
| Modül | Ne yapar |
|---|---|
| `M3U` | `M3UParser` (EXTINF öznitelikleri, EXTGRP, EXTVLCOPT, KODIPROP, CRLF/BOM, boşluklu URL), `PlaylistSniffer` ("bu adres kanal listesi değil, medya akışı" tespiti), `PlaylistLoader` |
| `Xtream` | `XtreamCredentials` (adres normalleştirme, parola gizleme), `XtreamEndpoints` (tüm `player_api.php` eylemleri ve akış URL'leri), toleranslı DTO'lar, `XtreamClient` |
| `EPG` | `XMLTVParser` (akışlı SAX), `EPGStore` (şimdi/sonraki, aralık sorgusu, `tvg-id` eşleme) |
| `Networking` | `HTTPTransport` protokolü, `URLSessionTransport` (zaman aşımı, User-Agent, yönlendirme politikası) |
| `Models` | `Channel`, `ChannelGroup`, `Playlist`, `MediaSource`, `StreamKind`, `MediaContainer`, `EPGChannel`, `Programme` |

## Derleme ve test
```bash
swift build
swift test
```
Windows kurulumu ve ortam değişkenleri için `CLAUDE.md`'ye bakın.

## Kullanım örneği
```swift
let playlist = try await PlaylistLoader().load(from: listURL)
let client = XtreamClient(credentials: try XtreamCredentials(baseURL: "sunucu.example.com:8080",
                                                             username: "kullanici", password: parola))
let hesap = try await client.accountInfo()
let rehber = try XMLTVParser.parse(fileURL: rehberDosyasi).makeStore()
let simdi = rehber.current(for: rehber.resolveChannelID(for: kanal) ?? "", at: .now)
```
