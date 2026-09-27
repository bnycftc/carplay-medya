# Durum — 2026-09-26

## Nerede kaldık (2026-09-26)
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
- EV3 testi (26 Eylül): arabada ses var, görüntü yok — beklenen (yalnız CarPlay Audio yetkisi; resmi video için Apple video yetkisi + Kia desteği gerekli, Kia henüz açmadı). bny kutu (AI box) yolunu istemedi; uygulama üzerinden devam kararı.
- Testler: Core 95, Kit 59 (Windows + macOS CI yeşil); iOS derleme ve TestFlight yeşil.
- Çalışma modu: orkestrasyon kapalı, oturum doğrudan Opus 5.5 ile yürüyor (bny kararı 26 Eylül).

## Bekleyenler
1. **Kia EV3'te CarPlay ses testi** (simge, sekmeler, oynatma, direksiyon tuşları) ve 0.2.0'ın telefonda denenmesi (film/dizi, devam et, rehber, arşiv). Sonuca göre düzeltme + yeni build (`gh workflow run testflight.yml`).
2. Apple **CarPlay Video** entitlement cevabı (Case-ID 22408601). Gelince `App/CarMedya/CarMedya.entitlements` dosyasına `com.apple.developer.carplay-video` geri eklenir ve App ID'de capability açılır.
3. App Store Connect **Paid Apps** sözleşmesi (banka/vergi) — abonelik için şart, bny yapacak.
4. Uygulama adı: "CarMedya" alınmış, kayıt "CarMedya Player"; yayın öncesi karar.
5. Hareket kilidi isteğe bağlı (Ayarlar'da anahtar var, varsayılan açık).

## Kararlar
- Ekran yansıtma **eklenmeyecek** (navigasyon yetkisini yanlış beyanla almak gerekir; Apple emsalleri kapattı). bny istemeye devam ediyor; CarTV iOS 27.0 + EV3'te çalışıyor, 27.2 betada kırık.
- Bulut imzalama bu hesapta çalışmıyor (takım adında "Ç"); saklı Apple Distribution sertifikası kullanılıyor. Anahtar ve p12: `C:\Users\bny\.carmedya-signing\` (repo dışı).

## Hızlı komutlar
- Paket testleri (Windows): CLAUDE.md'deki PowerShell bloğu.
- TestFlight build: `gh workflow run testflight.yml` → App Store Connect'te "Dahili Test" grubuna otomatik düşer.
