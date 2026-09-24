# Durum — 2026-09-24 gece

## Nerede kaldık
- **Faz 1-3 tamam ve cihazda doğrulandı.** CarMedya Player 0.1.0 (5) TestFlight ile bny'nin iPhone'unda (iOS 27.0): onboarding, M3U/Xtream kaynak, kanal listesi, oynatma, kilit ekranı kontrolleri, favoriler, arama, ayarlar çalışıyor.
- **Faz 4 başlatıldı ama durduruldu, kod yazılmadı.** Kapsam: Xtream film/dizi kataloğu (poster grid, detay, sezon/bölüm), izlemeye devam, EPG rehber ekranı (şimdi/sonra, zaman çizelgesi, gzip XMLTV), arşiv/catch-up oynatma, sürüm 0.2.0. Yeniden başlatırken Opus'a bu kapsamı ver; Core/Kit Foundation-only kalır, gzip yalnız App katmanında.

## Bekleyenler
1. **25 Eylül: Kia EV3'te CarPlay ses testi** (simge, sekmeler, oynatma, direksiyon tuşları). Sonuca göre düzeltme + yeni build (`gh workflow run testflight.yml`).
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
