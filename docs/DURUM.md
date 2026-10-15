# Durum — 2026-10-15

## YENİDEN BAŞLADI (2026-10-15)
- **Tetik:** Apple CarPlay Video yetkisini verdi (Case 22408601, 2026-10-15). Dondurma sona erdi; yeni sürüm 0.7.0.
- **Karar: yalnız `carplay-audio` kullanılır, `carplay-video` bilerek kullanılmaz.** Apple CarPlay Developer Guide (Ekim 2026): ses kategorisi "ses ya da ses+video karışımı" oynatır (s.4); video uygulamaları videosuz araçlarda gizlenir (s.4); kategoriler tek uygulamada birleşmez (s.4); video sunan ses uygulaması AirPlay video desteklemelidir (s.5). bny'nin Kia EV3'ü video desteklemiyor; video yetkili uygulama orada kaybolurdu. App ID'de yalnız "CarPlay Audio App (CarPlay framework)" açık; "CarPlay Video" kutusu kapalı (portalda doğrulandı, 2026-10-15). Görüntü AirPlay video ile sistem tarafından sunulur; uygulama yalnız CarPlay şablonları + `CPPlaybackConfiguration` üstverisi verir.
- **Gerçek durum (EV3):** Ekim 2026 başı itibarıyla hiçbir üretici CarPlay "araçta video" desteğini duyurmadı; Kia'nın EV3 güncelleme notlarında da yok. EV3 bugün yalnız ses gösterir. Araçta video yalnız bu özelliği olan araçlarda ve yalnız park halinde çalışır; kısıtı araç uygular.
- **0.7.0 içeriği:** iOS 27 CarPlay video üstverisi — `CPSessionConfiguration.supportsVideoPlayback` + satırlarda `CPPlaybackConfiguration` (satır `.video`/`.audio` işaretli, oynat/duraklat eylemi senkron); yalnız araç videoyu destekliyorsa ve yeni "Park halinde araç ekranında video" ayarı açıksa (varsayılan **kapalı**, bny kararı 2026-10-15). Videosuz araçta (EV3) davranış 0.6.1 ile aynı. Tanılama logları (`isExternalPlaybackActive`, rota değişim nedenleri). CI "xcode-27" GitHub runner'ına taşındı, Xcode 27.0 `DEVELOPER_DIR` ile sabit (iOS 27 SDK; macos-15/26'da yok; beta App Store Connect'te reddedilir). TestFlight adımı imzalı entitlement'ın yalnız ses olduğunu doğrular.
- **Telefonda tarayıcı (bny talimatı, 2026-10-15):** Ana Sayfa sağ üst "Tarayıcı" → adres ya da arama, sayfa `SFSafariViewController` ile yalnız telefonda açılır (`BrowserView`; adres/arama ayrımı `CarMediaKit` `BrowserAddress`, yalnız http(s)). CarPlay'de web gösterilmez (yalnız şablonlar); ekran yansıtma eklenmedi (kırmızı çizgi). Arama motoru varsayılan Google (`BrowserView.searchTemplate`); bny başka motor isterse tek satır değişir.
- **`carplay-medya-plani.md` §2.4 "Audio + Video birlikte" geçersiz:** Apple'ın Ekim 2026 Guide'ı ve e-postası bunun yerine geçti (plan dosyası değiştirilmedi).
- **CarTV:** App Store sayfasına göre tüm iPhone ekranını arabaya yansıtıyor = ekran yansıtma, kırmızı çizgimiz; kopyalanmaz.
- **App Store'a göndermeden önce:** App Review notlarına uygulamanın CarPlay ses yetkisi altında ses + video karıştırdığını yaz (Case 22408601, Guide s.4–5).
- **`carmedya-watch` görevi:** Apple tetiği ateşlendi; yalnız üretici/EV3 haberlerini arayacak şekilde daraltılıyor (ana ajan yapıyor).

## Dondurma dönemi (2026-09-28 → 2026-10-15, SONA ERDİ)
- **Neden:** bny'nin hedefi gelir; projenin tek gerçek farkı arabada videoydu ve bu bugün meşru yoldan imkânsız. iOS 27 resmi CarPlay videosu = `com.apple.developer.carplay-video` + CarPlay tarama şablonları + görüntü AirPlay video ile, yalnız park halinde ve araç üreticisinin "video in car" (MFi) desteğiyle. 17 Eylül 2026 itibarıyla hiçbir üretici desteklemiyor (Kia EV3 dahil). CarTV'nin arabadaki görüntüsü CarPlay bağlantısı üzerinden ekran yansıtma; iOS 27.2'de kırılıyor. Telefonda görüntü sorunsuz (bny doğruladı).
- Yeni özellik yazılmadı; uygulama TestFlight'ta 0.6.1 (17) olarak kaldı. Yeniden başlatma tetikleri (a) Apple cevabı (geldi: 2026-10-15), (b) üretici "video in car" desteği, (c) EV3'te "Car Video Check" görünmesi. `carmedya-watch` görevi (Pzt ve Per 10:00) bunları izliyordu.
- Önceki "yetki gelince ilk iş: entitlement'ı geri ekle" planı iptal: yetki bilerek kullanılmıyor (yukarıdaki karar).


## Nerede kaldık (2026-10-15)
- **0.7.0 (hazırlanıyor, 2026-10-15):** iOS 27 CarPlay video üstverisi (`supportsVideoPlayback` + `CPPlaybackConfiguration`), "Park halinde araç ekranında video" ayarı (varsayılan kapalı), telefonda tarayıcı, tanılama logları, CI xcode-27 runner'ı + Xcode 27.0 sabitleme, TestFlight'ta ses-yalnız entitlement doğrulaması. Ayrıntı yukarıda. Henüz TestFlight'a yüklenmedi.
- **Faz 1-3 cihazda doğrulandı** (0.1.0 (5), iPhone iOS 27.0).
- **Faz 4 tamam, 0.2.0 (8) TestFlight'a yüklendi** (Apple'da işleniyor, "Dahili Test" grubuna otomatik düşer):
  - "Filmler ve Diziler" sekmesi: Xtream film/dizi kataloğu, poster ızgarası, kategori çipleri, arama, sıralama.
  - Film ve dizi detayları: sezon/bölüm listesi, izlendi işareti, desteklenmeyen biçim (MKV vb.) uyarısı.
  - İzlemeye devam: 60 sn'den sonra kaydeder, %95'te izlendi sayar, URL/parola saklamaz (`continue-watching.json`).
  - Rehber: Kütüphane sağ üstte "Rehber"; EPG'li kanallar, dün–yarın program listesi, arşivli kanallarda geçmiş programı "Arşivden izle" (Xtream timeshift HLS; M3U catchup default/append/shift/flussonic).
  - `.xml.gz` rehberler açılıyor (gzip çerçevesi Core'da, açma App'te `NSData.decompressed(.zlib)`).
  - Ayarlar: izleme geçmişini temizle.
- **0.2.1**: CarPlay bağlıyken telefonda video gizlenmesi düzeltildi (hız bilinmiyorsa video görünür, hareket kuralı varsayılan kapalı); video içerikte ses oturumu `.longFormVideo`.
- **0.3.0 TestFlight'ta**: Ana Sayfa sekmesi (şimdi oynuyor, izlemeye devam, favori kanallar, son izlenenler, yeni film/dizi) ve Siri komutları ("CarMedya'da <kanal> aç", "son kanalı aç", "durdur").
- **0.4.0 TestFlight'ta** (kullanılabilirlik): "Bağlantı veya mesaj yapıştır" (get.php → Xtream otomatik, sağlayıcı mesajı okuma), M3U→Xtream dönüştürme önerisi, canlı yayında 3 kez otomatik yeniden bağlanma (+15 sn takılma algılama), grup gizleme (Canlı TV + CarPlay), oynatıcıda kanal listesi, uyku zamanlayıcı. Testler Kit 73 / Core 95.
- **0.4.1 TestFlight'ta** (Fable incelemesi → Opus düzeltmesi): yeniden bağlanma sırasında duraklatma kilidi, saniyelik yayın yükü, Keychain okuma sayısı, Siri soğuk başlatma taraması düzeltildi; dizi bölümü bitince sonraki bölüme geçiş eklendi (Ayarlar > Oynatma). Testler Kit 74 / Core 95. Bekleyen notlar: Xtream arşiv saat dilimi gerçek sağlayıcıda denenmedi; katalog disk önbelleği yok (her açılışta indirir); sağlayıcı mesajında hesap yoksa ilk web adresi M3U sanılabilir.
- **0.5.0 TestFlight'ta** (27 Eylül): film/dizi kataloğu disk önbelleği (anında açılış, 6 saatte arka plan yenileme, ağ hatasında önbellek kalır) ve CarPlay'de dördüncü sekme "A–Z" (harfle kanal bulma; klavyeli arama CarPlay ses uygulamalarında yok, sesli arama Siri ile). Ekran yansıtma talebi tekrar geldi, reddedildi (CarPlay kısıtlamasını aşmayı gerektiriyor).
- **0.5.1 TestFlight'ta** (27 Eylül): oynatıcının altında kanal listesi (bny'nin ekran görüntüsündeki isteği). CI tuzağı çözüldü: otomatik imzalama her koşuda 'Created via API' geliştirme sertifikası üretip hesabı sınıra dayandırmıştı; 11 eski sertifika iptal edildi, iş akışı artık her koşu sonunda bunları API ile iptal ediyor (dağıtım sertifikası Q9GHLHVX8G korunuyor).
- **Varsayılan içerik araştırması (27 Eylül):** güvenli seçenek yalnız kendi sunucumuzda barındırılan küratörlü liste — Blender açık filmleri (CC-BY), NASA video arşivi (kamu malı), isteğe bağlı TR+ABD'de kamu malı olduğu doğrulanmış sessiz filmler. Canlı TV kanalları (TRT, DW, Euronews vb.) üçüncü taraf uygulamaya izin vermiyor; archive.org canlı API'si 'yalnız araştırma' şartlı ve etiketleri güvenilmez; Radio Browser App Review'da 5.2.3 reddi geçmişi var. bny kararı bekleniyor.
- EV3 testi (26 Eylül): arabada ses var, görüntü yok. Bu test video kodu olmayan bir build'le yapıldı; aracın video desteğini ölçmedi (video koduyla EV3 henüz denenmedi). bny kutu (AI box) yolunu istemedi; uygulama üzerinden devam kararı.
- **0.6.0 TestFlight'ta** (27 Eylül): ücretsiz örnek paket (Blender + NASA), Ana Sayfa hoş geldin kartı ve arama, Canlı TV grup çipleri, yatay tam ekran oynatıcı, Lisanslar ekranı.
- **0.6.1 (17) TestFlight'ta** (27 Eylül): CarPlay ve kilit ekranında kanal logosu her zaman görünür (logo yoksa baş harfler; şeffaf logo zıt zeminde). Arabada doğrulanmadı.
- Testler: Core 95, Kit 59 (Windows + macOS CI yeşil); iOS derleme ve TestFlight yeşil.
- Çalışma modu: orkestrasyon kapalı, oturum doğrudan Opus 5.5 ile yürüyor (bny kararı 26 Eylül).

## Bekleyenler
1. **Kia EV3 testi** (simge, sekmeler, oynatma, direksiyon tuşları). Araç video desteğini bny şöyle sınar:
   1. "Car Video Check" (App Store id6812248899) kur: EV3 CarPlay ana ekranında görünmezse ya da "desteklenmiyor" derse araçta video yok.
   2. Telefondaki CarMedya'da, park halinde ve CarPlay bağlıyken bir Blender örneğini oynat, oynatıcıda AirPlay düğmesine bas: araç ekranı listede yoksa araçta video yok.
   3. TestFlight 0.7.0 EV3'te 0.6.1 ile birebir aynı görünmeli ve davranmalı (boş ekran yok, çift Now Playing yok).
   Sonuca göre düzeltme + yeni build (`gh workflow run testflight.yml`).
2. ~~Apple CarPlay Video entitlement cevabı~~ **Çözüldü (2026-10-15):** verildi, bilerek kullanılmıyor; yalnız ses yetkisi (bkz. Kararlar). `carplay-video` dosyaya eklenmez, App ID'de kutu kapalı kalır. Yerine: App Store'a göndermeden önce App Review notları (ses+video karışımı, Case 22408601, Guide s.4–5).
3. App Store Connect **Paid Apps** sözleşmesi (banka/vergi) — abonelik için şart, bny yapacak.
4. Uygulama adı: "CarMedya" alınmış, kayıt "CarMedya Player"; yayın öncesi karar.
5. Hareket kilidi isteğe bağlı (Ayarlar'da anahtar var, varsayılan açık).

## Kararlar
- **Yalnız `carplay-audio` (2026-10-15):** `carplay-video` verildi ama kullanılmıyor — videosuz araçta (EV3) uygulama kaybolurdu; Apple Guide ses kategorisinde ses+video karışımına AirPlay video şartıyla izin veriyor. Ayrıntı "YENİDEN BAŞLADI" bölümünde.
- Ekran yansıtma **eklenmeyecek** (navigasyon yetkisini yanlış beyanla almak gerekir; Apple emsalleri kapattı). bny istemeye devam ediyor; CarTV iOS 27.0 + EV3'te çalışıyor, 27.2 betada kırık. CarTV kendi App Store sayfasına göre tüm iPhone ekranını yansıtıyor (2026-10-15 incelemesi); reddi sürüyor.
- Bulut imzalama bu hesapta çalışmıyor (takım adında "Ç"); saklı Apple Distribution sertifikası kullanılıyor. Anahtar ve p12: `C:\Users\bny\.carmedya-signing\` (repo dışı).

## Hızlı komutlar
- Paket testleri (Windows): CLAUDE.md'deki PowerShell bloğu.
- TestFlight build: `gh workflow run testflight.yml` → App Store Connect'te "Dahili Test" grubuna otomatik düşer.
