import Foundation

/// Converts downloaded bytes to text, tolerating byte-order marks and legacy encodings.
public enum TextDecoding {
    /// Decodes `data` as text.
    ///
    /// Order: UTF-8 (BOM stripped), UTF-16 with BOM, Windows-1254 (Turkish), ISO-8859-1.
    /// Returns `nil` only for data that no attempted encoding accepts.
    public static func string(from data: Data) -> String? {
        if data.count >= 3, data[data.startIndex] == 0xEF, data[data.startIndex + 1] == 0xBB,
           data[data.startIndex + 2] == 0xBF {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if data.count >= 2 {
            let b0 = data[data.startIndex], b1 = data[data.startIndex + 1]
            if (b0 == 0xFF && b1 == 0xFE) || (b0 == 0xFE && b1 == 0xFF) {
                return String(data: data, encoding: .utf16).map(stripBOM)
            }
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return stripBOM(utf8)
        }
        if let turkish = String(data: data, encoding: .windowsCP1254) {
            return turkish
        }
        return String(data: data, encoding: .isoLatin1)
    }

    /// Removes a leading U+FEFF if present.
    static func stripBOM(_ string: String) -> String {
        string.hasPrefix("\u{FEFF}") ? String(string.dropFirst()) : string
    }

    /// Returns `true` when the bytes start with the gzip magic number (`1F 8B`).
    public static func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
    }
}
