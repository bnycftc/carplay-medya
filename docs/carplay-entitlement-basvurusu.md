# CarPlay Entitlement Başvurusu

Form: https://developer.apple.com/contact/request/carplay/
Hesap: Bünyamin Çiftci · Team ID 26322AY3MH · Tarih: 2026-09-22

Akış: App Type seç → CarPlay Entitlement Addendum kutusunu işaretle → "Agree" → "Tell us about your app" alanını doldur → gönder.
Form tek kategori alıyor. İki başvuru yapılacak: önce **Video**, sonra **Audio**. Metinler aşağıda; alan tek satır kabul ediyorsa kısa sürümü kullan.

---

## 1. Başvuru — App Type: Video

### Kısa sürüm (tek satırlık alan için)

Personal media player for CarPlay. Plays the user's own content only: local video/audio files, the user's own IPTV playlists (M3U/Xtream) and home media servers (Jellyfin/DLNA). We host, bundle or recommend no content. Playback is built on AVPlayer with HLS and supports AirPlay video streaming, so video plays on the car display only when the vehicle reports video support and is parked; otherwise the same item plays audio-only. CarPlay UI uses only List, Tab Bar, Now Playing, Search and Voice Control templates. We are also requesting the Audio entitlement so the app remains available in vehicles without video support, as recommended in WWDC26 session 212. Minimum iOS 27 for video features. Developer: individual, Türkiye.

### Uzun sürüm (çok satırlı alan için)

App (working title): CarPlay personal media player. Bundle ID will be created under Team 26322AY3MH once the entitlement is granted.

What it does
- Plays media the user already owns or has access to: local video and audio files imported via Files/Share Sheet, the user's own IPTV playlists (M3U/M3U8 and Xtream Codes accounts), and the user's own home media servers (Jellyfin, DLNA/UPnP).
- The app ships empty. It does not host, bundle, sell, recommend or link to any channels, playlists or third-party streaming catalogs. Users add their own sources. Screenshots and marketing contain no third-party channel branding.

Why Video entitlement
- The app is primarily designed to provide video playback services (Addendum 3.13): live channels, on-demand video and local files.
- Playback is built on AVPlayer/AVQueuePlayer with HLS, MP4 and audio formats, and supports AirPlay video streaming (allowsExternalPlayback), as required by the CarPlay Developer Guide for video apps.
- We use CPPlaybackConfiguration with preferredPresentation .video and CPPlayableItem, CPThumbnailImage and CPListTemplateDetailsHeader. When CPSessionConfiguration.supportsVideoPlayback is false or video availability changes mid-session, the same item plays audio-only. No screen mirroring, no custom drawing on the car display.

Driver safety
- All CarPlay flows are completable without touching iPhone. Templates only: Tab Bar, List, Now Playing (with MiniPlayer), Search, Voice Control. No gaming, social, commerce, lyrics or web browsing on the car screen.
- Video is available only while parked as enforced by the vehicle/CarPlay system; the app additionally degrades to audio when the phone reports motion.

Related request
- We are separately requesting the Audio entitlement (Addendum 3.4: radio streams, audio playlists, audio-only playback of the same sources) so the app stays available in vehicles that do not support video, per WWDC26 session 212 guidance to combine both entitlements.

Compliance
- App Review Guidelines 5.2.1–5.2.3: no third-party content, no downloading/ripping, user supplies and is responsible for sources.
- Privacy: no analytics, no tracking; data stays on device/iCloud.
- Monetization: StoreKit 2 subscription and lifetime unlock with Family Sharing; no content is sold.

Timeline: core engine in development now; TestFlight build targeted within 8 weeks of entitlement grant. Test vehicle: Škoda Karoq (wired CarPlay) plus CarPlay Simulator with the video-capable vehicle configuration.

---

## 2. Başvuru — App Type: Audio

### Kısa sürüm

Companion request for the same app as our Video entitlement request (personal media player, Team 26322AY3MH). In CarPlay audio mode the app is primarily an audio playback service: the user's own internet radio streams and audio channels from their M3U/Xtream playlists, local audio files and audio-only playback of any source. No content is hosted, bundled or recommended; users add their own sources. Templates: Tab Bar, List, Now Playing, Search, Voice Control. No lyrics, browsing, commerce or messaging. Requested alongside Video per WWDC26 session 212 so the app remains available in vehicles without video support.

### Uzun sürüm

Same app as our Video entitlement request (Team 26322AY3MH).

Audio role (Addendum 3.4)
- Internet radio and audio channels from the user's own M3U/Xtream playlists, local audio files, and audio-only playback of every source (live, VOD, local) when the vehicle does not support video or is in motion.
- Now Playing template with live-stream support, MiniPlayer, Tab Bar (Favorites / Channels / Recent / Search), List, Search and Voice Control templates. No lyrics, no web browser, no text-to-speech readers, no turn-by-turn.
- Audio session is activated only while playing, so the vehicle's own radio is never interrupted unnecessarily.

Content policy, safety, privacy and monetization: identical to the Video request. The app ships without any content; users supply their own sources.

---

## Gönderdikten sonra
- Apple onayı e-postayla gelir (birkaç günden birkaç haftaya). Onay "Certificates, Identifiers & Profiles" altında yeni bir App ID capability olarak görünür.
- Onay geldiğinde: App ID oluştur, entitlement'ı provisioning profile'a ekle, Xcode projesine `com.apple.developer.carplay-video` ve `com.apple.developer.carplay-audio` anahtarlarını koy.
- Ret gelirse: gerekçeyi kaydet, uygulama TestFlight'ta çalışır haldeyken yeniden başvur (Apple "henüz yapılmamış uygulama" gerekçesiyle reddedebiliyor).
