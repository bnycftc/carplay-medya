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
