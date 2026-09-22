# CarPlay Medya Oynatıcı — Hedef, Strateji, Yol Haritası ve Teknik Brief

Tarih: 2026-09-22 · Durum: planlama · Karar: yalnız Apple'ın onayladığı yollar, gri yöntem yok.

---

## 1. Hedef

Kullanıcının **kendi içeriğini** (yerel dosya, kendi IPTV listesi, DLNA/Jellyfin sunucusu) telefonda ve CarPlay ekranında oynatan, App Store'da kalıcı, meşru bir medya uygulaması.

- **Bugün:** CarPlay'de ses (radyo, IPTV ses kanalları, podcast benzeri akışlar) + telefonda tam video.
- **Araç üreticileri açtığında:** aynı uygulama CarPlay ekranında park halinde video oynatır, kod değişikliği gerekmeden.
- **Fark:** CarTV'nin ekran yansıtma hilesi yerine Apple'ın resmi "video app" kategorisi. Kaldırılma riski yok, iOS güncellemesiyle kırılmaz.

**Başarı ölçütleri**
1. Audio + video entitlement alınmış, App Review'dan geçmiş (v1.0 yayında).
2. CarPlay Simulator'da video senaryosu çalışıyor (Apple'ın "video destekli araç" konfigürasyonuyla).
3. İlk 90 günde ≥ 1.000 indirme (TR), ≥ 4,3 puan, iade oranı < %5.
4. Sıfır 5.2.x (üçüncü taraf içerik) şikayeti: uygulama hiçbir kanal listesi taşımıyor.

---

## 2. Strateji

### 2.1 Neden şimdi
- iOS 27 (14 Eylül 2026) resmi CarPlay video kategorisini getirdi. Henüz **hiçbir araç üreticisi** desteği açmadı. İlk üretici açtığında hazır olan meşru uygulama kazanır.
- CarTV 5 haftada 2.500 oy aldı, TR Utilities'de #1. Talep kanıtlandı. Ama ürünü gri; ilk Apple müdahalesinde boşluk oluşur.
- Kategori boş: Apple TV uygulaması ve birkaç yeni indie (TurboTurtle, Car Video Check) dışında rakip yok.

### 2.2 Konumlandırma
"Kendi içeriğin, arabanda, kurallara uygun." Vaat edilmeyenler açıkça yazılır: Netflix/Disney+/YouTube oynatılmaz, sürüş sırasında video oynamaz.

### 2.3 Ürün ilkeleri
1. **İçerik sağlamıyoruz.** Uygulama boş gelir; kullanıcı listesini, sunucusunu, dosyasını ekler. Önerilen kanal, örnek liste, iptv-org bağlantısı yok. Ekran görüntülerinde telifli logo yok.
2. **AVPlayer + HLS çekirdek.** CarPlay video yolu yalnız AirPlay video üzerinden çalışır, bu da yalnız AVPlayer ile mümkün. VLCKit tarzı motorlar CarPlay video'ya çıkamaz; en fazla telefon içi yedek olarak düşünülür.
3. **Sürücü güvenliği yerleşik.** Hareket halinde video → yalnız ses. Bunu araç sinyali yapar; biz ek olarak GPS hız eşiğiyle telefonda da uygularız.
4. **Dürüst para modeli.** Sabit fiyat, 7 gün deneme, Aile Paylaşımı, iCloud ile cihazlar arası geçiş, fiyat oynatma yok.

### 2.4 Entitlement stratejisi
- **Audio + Video birlikte** başvur (Apple WWDC26'da bunu açıkça öneriyor). Yalnız video alınırsa uygulama video desteklemeyen araçlarda CarPlay'de hiç görünmez.
- Başvuru formu: https://developer.apple.com/contact/request/carplay/ — süre birkaç günden aylara. **Bu yüzden ilk iş başvuru.**
- Başvuru metninde: "primarily audio/video playback", kullanıcı kendi içeriğini getirir, hareket halinde yalnız ses, CarPlay şablonları amacına uygun.
- Ret senaryosu: audio reddedilirse radyo/IPTV-ses ayrı bir "audio-first" uygulama olarak bölünür.

### 2.5 Pazar sırası
1. Türkiye (TR arayüz, TRY fiyat, Türkçe destek).
2. Körfez (CarTV'nin puanlarının %70'i Suudi/BAE/Kuveyt; Arapça yerelleştirme).
3. Global (EN, DE).

---

## 3. Ürün kapsamı

### v1.0 — MVP (CarPlay ses + telefon video)
- Kaynaklar: M3U/M3U8 URL, Xtream Codes hesabı, yerel dosya (Files/Paylaş menüsü), Jellyfin sunucu.
- Telefon: kanal listesi, gruplar, favoriler, arama, EPG (XMLTV), AVPlayer tam ekran, PiP, AirPlay düğmesi.
- CarPlay: Tab bar (Favoriler / Kanallar / Son Oynatılan / Arama), List template, Now Playing (canlı akış), MiniPlayer.
- Arka plan ses, kilit ekranı kontrolleri, Now Playing framework (iOS 27).
- Satın alma: StoreKit 2, aylık/yıllık/ömür boyu, Aile Paylaşımı.
- Onboarding: "içerik sağlamıyoruz" + güvenlik uyarısı + kaynak ekleme.

### v1.1 — CarPlay video hazırlığı
- `CPPlaybackConfiguration(.video)`, `CPPlayableItem`, `CPThumbnailImage` ile video liste akışı.
- `supportsVideoPlayback` ile koşullu sunum; video yoksa aynı öğe ses olarak oynar.
- CarPlay Simulator "video destekli araç" konfigürasyonuyla test.
- Search template ve Voice control template.

### v1.2 — Kaynak genişletme
- DLNA/UPnP (SwiftUPnP + multicast entitlement başvurusu).
- Emby, Plex (API şartları doğrulanınca), WebDAV/SMB.
- Xtream VOD/dizi katalogları, izlemeye devam.

### v2 — Farklılaştırıcılar
- Çoklu profil (aile), çocuk kilidi.
- Cihazda HLS'e remux (MKV/TS → AirPlay video) — teknik olarak doğrulanırsa.
- CarPlay widget ve Live Activity (iOS 26+): "şimdi çalıyor", hızlı favoriler.
- Android Auto (ayrı araştırma).

**Kapsam dışı (kalıcı):** ekran yansıtma, Netflix/Disney+/beIN gibi DRM içerik, YouTube (API politikası arka plan ve ayrıştırmayı yasaklıyor), önyüklü kanal listeleri.

---

## 4. Yol haritası

| Faz | Süre | Çıktı | Doğrulama |
|---|---|---|---|
| 0. Kurulum | Hafta 1 | Apple Developer hesabı (bireysel, D-U-N-S gerekmez), Bundle ID, CarPlay audio+video entitlement başvurusu, multicast başvurusu, marka adı ve domain | Başvurular gönderildi, hesap aktif |
| 1. Çekirdek oynatıcı | Hafta 2–4 | M3U/Xtream parser, model katmanı (SwiftData), AVPlayer servisi, HLS/MP4 oynatma, arka plan ses, EPG parser | Birim testleri; 3 farklı gerçek listeyle manuel test |
| 2. Telefon arayüzü | Hafta 4–6 | SwiftUI: kaynak ekleme, liste, EPG, favoriler, oynatıcı, ayarlar, onboarding | TestFlight iç test |
| 3. CarPlay ses | Hafta 5–7 | Scene delegate, Tab bar/List/Now Playing, MiniPlayer, Now Playing framework | Xcode CarPlay simülatörü + gerçek araçta kablolu/kablosuz test |
| 4. Para + hukuk | Hafta 6–8 | StoreKit 2, RevenueCat (isteğe bağlı), gizlilik etiketi, KVKK/GDPR metni, App Store metni ("içerik sağlamıyoruz") | Sandbox satın alma; avukat görüşü (RTÜK 29/A, FSEK) |
| 5. Yayın v1.0 | Hafta 8–10 | App Review gönderimi, ATS gerekçesi, ekran görüntüleri (telifsiz) | Onay; ret olursa 5.2.x için hak kanıtı akışı hazır |
| 6. CarPlay video (v1.1) | Hafta 10–14 | Video playback config, thumbnail, details header, Search/Voice template | CarPlay Simulator video konfigürasyonu |
| 7. Kaynak genişletme (v1.2) | Hafta 14–20 | DLNA, Jellyfin/Emby, VOD | Gerçek sunucularla test |

Kritik yol: entitlement onayı. Faz 1–2 entitlement olmadan ilerler; Faz 3 simülatörde entitlement olmadan **çalışmaz** (Xcode simülatörü entitlement ister). Onay gecikirse Faz 3 geriye kayar, telefon sürümü TestFlight'a çıkar.

**Karar noktaları**
- Hafta 6: entitlement geldi mi? Gelmediyse Apple'a takip, yayın planı telefon-öncelikli.
- 2027 ortası: hâlâ hiçbir üretici video açmadıysa CarPlay video önceliği düşer, AirPlay + telefon deneyimine yatırım.

---

## 5. Teknik mimari

```
┌─ App (SwiftUI) ───────────────┐   ┌─ CarPlay Scene ────────────────┐
│ Sources · Library · EPG · Player │   │ CPTabBar → CPList → CPNowPlaying │
└──────────────┬────────────────┘   └───────────────┬────────────────┘
               │                                    │
        ┌──────▼────────────────────────────────────▼──────┐
        │ Core (Swift Package)                              │
        │  SourceProviders: M3U · Xtream · Local · Jellyfin · DLNA │
        │  Catalog (SwiftData) · EPGStore · Favorites       │
        │  PlaybackService (AVPlayer, AVQueuePlayer)         │
        │  NowPlaying (MediaSession, iOS 27)                 │
        │  Entitlements/Capabilities probe                    │
        └────────────────────────────────────────────────────┘
```

- **Dil/çatı:** Swift 6, SwiftUI (telefon), CarPlay framework CP* şablonları (SwiftUI CarPlay UI yok), SwiftData, Swift Concurrency.
- **Min iOS:** 17 (telefon), CarPlay video özellikleri iOS 27'de koşullu (`@available`).
- **Oynatıcı:** AVPlayer. `allowsExternalPlayback = true`, `usesExternalPlaybackWhileExternalScreenIsActive = true`. AVRoutePickerView `prioritizesVideoDevices = true`.
- **Ses oturumu:** `.playback` kategori, `.longFormAudio` policy; yalnız oynatma anında aktif et (aksi halde araç radyosunu keser). `UIBackgroundModes: audio`.
- **Formatlar:** HLS (.m3u8), MP4/MOV, MP3/AAC. Xtream'de `.ts` yerine `.m3u8` çıktısı iste. MKV/RTSP/UDP desteklenmez (açıkça belirt).
- **CarPlay:** `UIApplicationSceneManifest` içinde `CPTemplateApplicationSceneSessionRoleApplication`, `CPTemplateApplicationSceneDelegate`. Dashboard/cluster sahnesi gerekmez.
- **Video (iOS 27):** `CPSessionConfiguration.supportsVideoPlayback`, `CPPlaybackConfiguration(preferredPresentation: .video)`, `CPPlayableItem`, `CPThumbnailImage`, `CPListTemplateDetailsHeader`. Video kullanılamazsa otomatik sese düşer.
- **Now Playing:** iOS 27'de `MediaSession`/`RemoteMediaSessionExtension`; MPNowPlayingInfoCenter ile karıştırma (tanımsız davranış).
- **Ağ:** ATS için `NSAllowsArbitraryLoads` + gerekçe ("kullanıcının kendi http kaynakları"). `NSLocalNetworkUsageDescription`. DLNA için `com.apple.developer.networking.multicast` (Apple izni gerekir).
- **Veri koruma:** kilitli telefonda CarPlay çalışmalı → `NSFileProtectionCompleteUntilFirstUserAuthentication`, Keychain `AfterFirstUnlock`.
- **Parser:** M3U (`#EXTINF`, tvg-id, tvg-logo, group-title) in-house; XMLTV için Foundation `XMLParser` (akış, büyük dosya). Hazır kütüphaneler ya arşivli (M3UKit) ya GPL (XMLTV) — kullanma.
- **Xtream API:** `player_api.php?username&password&action=get_live_categories|get_live_streams|get_vod_streams|get_series|get_short_epg`, EPG `xmltv.php`. Akış: `/live|movie|series/{user}/{pass}/{id}.m3u8`.
- **Jellyfin:** açık API, HLS transcode uç noktaları; kullanıcı kendi sunucusu.
- **Satın alma:** StoreKit 2, `Product.isFamilyShareable`, ömür boyu = non-consumable. RevenueCat 2,5k$/ay'a kadar ücretsiz.
- **Test:** Xcode > I/O > External Displays > CarPlay (800×480@2x, entitlement şart). Video için "Additional Tools for Xcode" içindeki CarPlay Simulator, video destekli araç konfigürasyonu. Gerçek araç: Karoq kablolu + Carlinkit kablosuz dongle (yalnız kablosuz test için, video aracı yerine geçmez).
- **CI:** Xcode Cloud veya GitHub Actions + fastlane; TestFlight otomatik.

**Referans açık kaynak (MIT, okunabilir/kopyalanabilir):** mikehouse/Apple-TV-Player, bsogulcan/another-iptv-player, katoemba/SwiftUPnP. GPL/AGPL olanlar (Lume, AerioTV, KSPlayer) yalnız fikir için.

---

## 6. App Review ve hukuk kontrol listesi

- **5.2.1 / 5.2.2 / 5.2.3:** içerik sağlamıyoruz; listeleme metni Smarters/GSE/IPTVX kalıbında: "Uygulama içerik, kanal veya yayın sağlamaz, barındırmaz, önermez. Kullanıcı kendi kaynağını ekler." Ekran görüntülerinde örnek/telifsiz içerik.
- **3.1.2:** abonelik ≥ 7 gün, tüm cihazlarda çalışır, mevcut kullanıcıdan özellik geri alınmaz.
- **2.5.4:** arka plan ses yalnız gerçek oynatmada.
- **4.2.7:** yansıtma yok. **4.3(b):** klon görünmemek için CarPlay + Jellyfin + EPG paketi ayırt edici.
- **CarPlay kılavuzu:** "telefonu eline al" demeyen akışlar, şablonlar amacına uygun, oyun/sosyal yok, şarkı sözü yok.
- **Ret planı:** 5.2.3 gelirse "kullanıcı kendi kaynağı" açıklaması + demo hesabında yalnız kendi ürettiğimiz test akışı.
- **Türkiye:** 5651 (7590 ile yetki Siber Güvenlik Başkanlığı'nda), FSEK 71, RTÜK 6112 md. 29/A — içerik sağlamayan araç konumu; **avukat görüşü Faz 4'te**. Vergi: GVK mük. 20/B (%15 stopaj, 2026 sınırı ₺5,3M) — muhasebeci onayı.
- **Gizlilik:** telemetri yoksa "Veri Toplanmıyor" etiketi; RevenueCat kullanılırsa satın alma tanımlayıcıları beyan edilir.

---

## 7. Para modeli (TR referans)

| Plan | Öneri | Piyasa |
|---|---|---|
| Deneme | 7 gün, tam özellik | CarTV 40 dk |
| Aylık | ₺49,99 | IPTVX ₺46,99, UHF ₺39,99 |
| Yıllık | ₺399,99 | IPTVX ₺379,99, UHF ₺449,99 |
| Ömür boyu | ₺999,99 | CarTV ₺1.089,99, UHF ₺1.499,99 |

Small Business Program: %15 komisyon. Aile Paylaşımı açık. Fiyat değişikliği yılda en fazla bir kez, önceden duyurulur.

---

## 8. Riskler

| Risk | Olasılık | Etki | Önlem |
|---|---|---|---|
| Entitlement gecikmesi/ret | Orta | Yüksek | İlk gün başvuru; telefon-öncelikli yayın; audio ayrı uygulama planı |
| Hiçbir üretici video açmıyor (2027) | Orta | Orta | Ses + telefon değer yeterli; karar noktası 2027 ortası |
| 5.2.x reddi | Orta | Orta | İçeriksiz kalıp, hak kanıtı akışı, telifsiz görseller |
| Format sınırı (MKV/TS yok) | Yüksek | Orta | Açık iletişim; Xtream'de m3u8; v2'de remux araştırması |
| Korsan liste kullanıcı şikayetleri/hukuk | Orta | Orta | Liste sağlamama, avukat görüşü, ToS |
| 4.3(b) klon algısı | Düşük | Orta | CarPlay + EPG + Jellyfin farkı, düzenli güncelleme |

---

## 9. Açık sorular (ilk 2 haftada kapatılacak)

1. Entitlement formunun soruları ve CarPlay Entitlement Addendum metni (giriş gerektiriyor; hesap açılınca oku).
2. Oturum içinde video kullanılamaz olduğunu bildiren API/notification hangisi?
3. Araç AirPlay video'yu kablosuz CarPlay mi gerektiriyor; HLS URL'yi araç mı çekiyor, telefon mu gönderiyor? (http/self-signed IPTV kaynaklarını belirler.)
4. Resmi araç gereksinimleri (1920×1080 iddiası, codec).
5. Video-öncelikli IPTV uygulamasına Apple audio entitlement veriyor mu?
6. Plex API şartları; Plex/Jellyfin CarPlay video planı.
7. Cihazda HLS remux MKV/TS'i AirPlay video'ya güvenilir taşıyor mu?
8. Aile Paylaşımı açıldıktan sonra kapatılabiliyor mu; Developer Program güncel TRY ücreti.

---

## 10. Sonraki somut adım

1. Apple Developer hesabı aç (bireysel), Bundle ID ve marka adını belirle.
2. CarPlay audio + video entitlement başvurusunu gönder.
3. Opus'a Faz 1 şartnamesi: Swift Package "Core" (M3U/Xtream parser, SwiftData modeli, PlaybackService) + birim testleri.

---

## Kaynaklar (seçilmiş)
- CarPlay Developer Guide, Haziran 2026: https://developer.apple.com/download/files/CarPlay-Developer-Guide.pdf
- WWDC26 212 "Rev up your CarPlay app": https://developer.apple.com/videos/play/wwdc2026/212/
- WWDC26 312 Now Playing framework: https://developer.apple.com/videos/play/wwdc2026/312/
- Entitlement başvurusu: https://developer.apple.com/contact/request/carplay/
- CPPlaybackConfiguration: https://developer.apple.com/documentation/carplay/cpplaybackconfiguration
- supportsVideoPlayback: https://developer.apple.com/documentation/carplay/cpsessionconfiguration/supportsvideoplayback
- CarPlay Simulator: https://developer.apple.com/documentation/carplay/using-the-carplay-simulator
- App Review Guidelines (8 Haziran 2026): https://developer.apple.com/app-store/review/guidelines/
- AirPlay desteği: https://developer.apple.com/documentation/avfoundation/supporting-airplay-in-your-app
- Multicast entitlement: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast
- Xtream API: https://github.com/worldofiptvcom/xtream-codes-api-documentation
- SwiftUPnP: https://github.com/katoemba/SwiftUPnP
- Small Business Program: https://developer.apple.com/app-store/small-business-program/
- Family Sharing: https://developer.apple.com/documentation/storekit/supporting-family-sharing-in-your-app
- Araç desteği durumu: https://www.pocket-lint.com/ios-27-new-carplay-features-availability/ · https://9to5mac.com/2026/09/21/heres-everything-new-for-carplay-in-ios-27/
- YouTube geliştirici politikası: https://developers.google.com/youtube/terms/developer-policies
- Rakip: CarTV https://apps.apple.com/tr/app/cartv-m3u-iptv-player-cast/id6800211040
