import UIKit

/// Square artwork for Now Playing (lock screen, CarPlay) and CarPlay list rows.
///
/// Channel logos are often transparent PNGs (white logos vanish on a light background), SVGs that
/// UIKit cannot decode, or unreachable. CarPlay then shows a generic icon. So artwork is always
/// rendered here: the logo centred on a card whose colour contrasts with it, or — when there is no
/// logo — the channel's initials on a colour derived from its name.
enum ArtworkRenderer {
    /// Logo on a contrasting square card, or initials when `logo` is nil.
    static func artwork(logo: UIImage?, title: String, side: CGFloat = 600) -> UIImage {
        if let logo { return card(for: logo, side: side) }
        return initials(for: title, side: side)
    }

    // MARK: Logo card

    static func card(for logo: UIImage, side: CGFloat) -> UIImage {
        let size = CGSize(width: side, height: side)
        let hasAlpha = Self.hasTransparency(logo)
        let isLight = hasAlpha && Self.averageLuminance(of: logo) > 0.62
        let background: UIColor = isLight ? UIColor(white: 0.13, alpha: 1) : UIColor(white: 0.97, alpha: 1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            background.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            // Opaque images (posters, photos) fill more of the card than transparent logos.
            let inset = hasAlpha ? side * 0.16 : side * 0.04
            let box = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            logo.draw(in: aspectFit(logo.size, in: box))
        }
    }

    // MARK: Initials

    static func initials(for title: String, side: CGFloat) -> UIImage {
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let (top, bottom) = colors(for: title)
        let text = initialsText(title)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            }
            let font = UIFont.systemFont(ofSize: side * (text.count > 2 ? 0.3 : 0.38), weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let textSize = (text as NSString).size(withAttributes: attributes)
            let origin = CGPoint(x: (side - textSize.width) / 2, y: (side - textSize.height) / 2)
            (text as NSString).draw(at: origin, withAttributes: attributes)
        }
    }

    /// "ATV" → "ATV", "Show TV" → "SH", "TRT 1 HD" → "T1", "24" → "24".
    static func initialsText(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: #"\b(HD|FHD|UHD|4K|SD|TV)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        let words = cleaned.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "|" }).map(String.init)
        guard let first = words.first else {
            return String(title.prefix(2)).uppercased(with: Locale(identifier: "tr_TR"))
        }
        if words.count == 1 {
            // Short all-caps names (ATV, NTV, CNN) read better whole.
            if first.count <= 4, first == first.uppercased() { return first }
            return String(first.prefix(2)).uppercased(with: Locale(identifier: "tr_TR"))
        }
        let letters = words.prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.uppercased(with: Locale(identifier: "tr_TR"))
    }

    /// Stable, pleasant gradient per title (same channel, same colours on every device).
    static func colors(for title: String) -> (UIColor, UIColor) {
        var hash: UInt32 = 2166136261
        for byte in title.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16777619
        }
        let hue = CGFloat(hash % 360) / 360
        return (UIColor(hue: hue, saturation: 0.55, brightness: 0.62, alpha: 1),
                UIColor(hue: hue, saturation: 0.7, brightness: 0.38, alpha: 1))
    }

    // MARK: Helpers

    private static func aspectFit(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: box.midX - fitted.width / 2, y: box.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }

    private static func hasTransparency(_ image: UIImage) -> Bool {
        guard let alpha = image.cgImage?.alphaInfo else { return false }
        switch alpha {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    /// Alpha-weighted average luminance (0…1) of the visible pixels, sampled at 16×16.
    private static func averageLuminance(of image: UIImage) -> CGFloat {
        guard let cgImage = image.cgImage else { return 0.5 }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return 0.5 }
        var weighted: CGFloat = 0
        var totalAlpha: CGFloat = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let a = CGFloat(pixels[index + 3]) / 255
            guard a > 0.05 else { continue }
            // Premultiplied: divide by alpha to get the colour.
            let r = CGFloat(pixels[index]) / 255 / a
            let g = CGFloat(pixels[index + 1]) / 255 / a
            let b = CGFloat(pixels[index + 2]) / 255 / a
            weighted += (0.2126 * r + 0.7152 * g + 0.0722 * b) * a
            totalAlpha += a
        }
        return totalAlpha > 0 ? min(1, weighted / totalAlpha) : 0.5
    }
}
