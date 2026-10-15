import CarMediaKit
import Foundation

extension CarVideoDiagnosis {
    /// Localized status line for Settings > "Araç ekranında video".
    var title: String {
        switch self {
        case .notConnectedYet:
            return String(localized: "Henüz CarPlay bağlantısı görülmedi")
        case .systemTooOld:
            return String(localized: "iOS sürümü eski")
        case .carHasNoVideo:
            return String(localized: "Araç video desteği bildirmiyor")
        case .settingOff:
            return String(localized: "Araç video destekliyor, ayar kapalı")
        case .ready:
            return String(localized: "Hazır")
        case .videoNotShown:
            return String(localized: "Görüntü araç ekranına geçmedi")
        case .videoShown:
            return String(localized: "Video araç ekranında oynadı")
        }
    }

    /// Localized explanation shown under the status line.
    var message: String {
        switch self {
        case .notConnectedYet:
            return String(localized: "Uygulamayı araçta CarPlay ekranından bir kez açın; sonuç burada görünür.")
        case .systemTooOld:
            return String(localized: "Araç ekranında video iOS 27 ister; bu sürümde video yalnız ses olarak çalar.")
        case .carHasNoVideo:
            return String(localized: "Son bağlanan araç Apple'ın \"araçta video\" özelliğini bildirmedi. Bu araçta ayar açık olsa da video yalnız ses olarak çalar; Apple'ın izin verdiği yoldan araç ekranına görüntü gönderilemez.")
        case .settingOff:
            return String(localized: "Yukarıdaki ayarı açın; araç park halindeyken video araç ekranında oynar.")
        case .ready:
            return String(localized: "Araç video destekliyor ve ayar açık. Park halindeyken CarPlay'de bir video kanalı seçin.")
        case .videoNotShown:
            return String(localized: "Araç video destekliyor ve ayar açık, ama son denemede görüntü araç ekranına gitmedi. Araç park halinde değilse ya da o an video izni vermediyse video yalnız ses olarak çalar.")
        case .videoShown:
            return String(localized: "Son bağlantıda görüntü araç ekranına gitti.")
        }
    }

    /// SF Symbol for the status line.
    var symbol: String {
        switch self {
        case .notConnectedYet:
            return "car.circle"
        case .systemTooOld, .carHasNoVideo, .videoNotShown:
            return "exclamationmark.triangle"
        case .settingOff:
            return "switch.2"
        case .ready, .videoShown:
            return "checkmark.circle"
        }
    }
}
