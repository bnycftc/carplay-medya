import CarMediaKit
import Foundation

extension UserFacingError {
    /// Localized, secret-free message for the UI and CarPlay alerts.
    var message: String {
        switch self {
        case .network:
            return String(localized: "Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.")
        case .httpStatus(let code):
            return String(localized: "Sunucu bir hata döndürdü (HTTP \(code)).")
        case .authentication:
            return String(localized: "Kullanıcı adı veya parola sunucu tarafından reddedildi.")
        case .mediaStreamNotList:
            return String(localized: "Bu adres bir kanal listesi değil, tek bir yayın akışı.")
        case .notAChannelList:
            return String(localized: "Bu adreste bir kanal listesi bulunamadı.")
        case .emptyPlaylist:
            return String(localized: "Liste oynatılabilir kanal içermiyor.")
        case .invalidAddress:
            return String(localized: "Adres veya giriş bilgileri geçersiz.")
        case .unexpectedResponse:
            return String(localized: "Sunucu yanıtı anlaşılamadı.")
        case .compressedData:
            return String(localized: "Sıkıştırılmış (gzip) dosyalar desteklenmiyor.")
        case .unsupported(let reason):
            return reason.message
        case .missingPassword:
            return String(localized: "Hesabın parolası bulunamadı. Kaynağı silip yeniden ekleyin.")
        case .fileUnavailable:
            return String(localized: "İçe aktarılan dosya açılamadı.")
        case .unknown:
            return String(localized: "Beklenmeyen bir hata oluştu.")
        }
    }
}

extension UnsupportedReason {
    /// Why this format cannot be played (CLAUDE.md: say it explicitly).
    var message: String {
        switch self {
        case .matroska:
            return String(localized: "MKV dosyaları desteklenmiyor. HLS (.m3u8) veya MP4 kullanın.")
        case .rawTransportStream:
            return String(localized: "Ham MPEG-TS (.ts) yayınları desteklenmiyor. Sağlayıcınızdan HLS (.m3u8) çıktısı isteyin.")
        case .container:
            return String(localized: "Bu dosya biçimi desteklenmiyor. HLS (.m3u8) veya MP4 kullanın.")
        case .rtsp:
            return String(localized: "RTSP/RTMP yayınları desteklenmiyor.")
        case .udp:
            return String(localized: "UDP yayınları desteklenmiyor.")
        case .otherProtocol:
            return String(localized: "Bu yayın protokolü desteklenmiyor.")
        }
    }
}
