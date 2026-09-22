import Foundation

/// Percent-encoding helpers that behave identically on Apple platforms and Windows/Linux.
public enum PercentEncoding {
    private static let hexDigits: [UInt8] = Array("0123456789ABCDEF".utf8)

    /// Encodes everything except RFC 3986 unreserved characters (`A-Z a-z 0-9 - . _ ~`).
    ///
    /// Suitable for query values and single path segments. Notably encodes `+`, `&`, `=` and `/`,
    /// which PHP back-ends (Xtream) would otherwise misinterpret.
    public static func encodeComponent(_ string: String) -> String {
        var out = [UInt8]()
        out.reserveCapacity(string.utf8.count)
        for byte in string.utf8 {
            if isUnreserved(byte) {
                out.append(byte)
            } else {
                appendEscaped(byte, to: &out)
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Leniently turns user-supplied URL text into a `URL`.
    ///
    /// Spaces, non-ASCII characters and other invalid characters are percent-encoded, while
    /// existing valid `%XX` escapes and URL delimiters are preserved.
    /// Relative references are resolved against `baseURL` when given; otherwise a scheme is required.
    public static func lenientURL(_ raw: String, relativeTo baseURL: URL? = nil) -> URL? {
        // Fast paths matter: playlists can hold 100k URLs and URL parsing dominates import time.
        var text = raw
        if let first = text.utf8.first, let last = text.utf8.last, isWhitespace(first) || isWhitespace(last) {
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else { return nil }
        let bytes = Array(text.utf8)
        let encoded = bytes.allSatisfy(isAlwaysValid) ? text : encodeInvalidURLCharacters(text)
        let url: URL?
        if let baseURL, !hasScheme(bytes) {
            url = URL(string: encoded, relativeTo: baseURL)?.absoluteURL
        } else {
            url = URL(string: encoded)
        }
        guard let url, let scheme = url.scheme, !scheme.isEmpty else { return nil }
        return url
    }

    /// `true` if the text starts with an RFC 3986 scheme followed by `:`.
    private static func hasScheme(_ bytes: [UInt8]) -> Bool {
        guard let first = bytes.first, isAlpha(first) else { return false }
        for byte in bytes.dropFirst() {
            if byte == UInt8(ascii: ":") { return true }
            let ok = isAlpha(byte) || (byte >= 0x30 && byte <= 0x39)
                || byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-") || byte == UInt8(ascii: ".")
            if !ok { return false }
        }
        return false
    }

    private static func isAlpha(_ b: UInt8) -> Bool {
        (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
    }

    private static func isWhitespace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D || b == 0x0B || b == 0x0C
    }

    /// Characters that never need escaping (a `%` is excluded so its escape can be validated).
    private static func isAlwaysValid(_ b: UInt8) -> Bool {
        isUnreserved(b) || isURLDelimiter(b)
    }

    /// Percent-encodes characters that are not allowed anywhere in a URL.
    static func encodeInvalidURLCharacters(_ string: String) -> String {
        let bytes = Array(string.utf8)
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        for (i, byte) in bytes.enumerated() {
            if byte == UInt8(ascii: "%") {
                let isEscape = i + 2 < bytes.count && isHex(bytes[i + 1]) && isHex(bytes[i + 2])
                if isEscape {
                    out.append(byte)
                } else {
                    appendEscaped(byte, to: &out)
                }
            } else if isUnreserved(byte) || isURLDelimiter(byte) {
                out.append(byte)
            } else {
                appendEscaped(byte, to: &out)
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func appendEscaped(_ byte: UInt8, to out: inout [UInt8]) {
        out.append(UInt8(ascii: "%"))
        out.append(hexDigits[Int(byte >> 4)])
        out.append(hexDigits[Int(byte & 0x0F)])
    }

    private static func isUnreserved(_ b: UInt8) -> Bool {
        (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39)
            || b == UInt8(ascii: "-") || b == UInt8(ascii: ".") || b == UInt8(ascii: "_") || b == UInt8(ascii: "~")
    }

    private static func isURLDelimiter(_ b: UInt8) -> Bool {
        switch b {
        case UInt8(ascii: ":"), UInt8(ascii: "/"), UInt8(ascii: "?"), UInt8(ascii: "#"),
             UInt8(ascii: "["), UInt8(ascii: "]"), UInt8(ascii: "@"), UInt8(ascii: "!"),
             UInt8(ascii: "$"), UInt8(ascii: "&"), UInt8(ascii: "'"), UInt8(ascii: "("),
             UInt8(ascii: ")"), UInt8(ascii: "*"), UInt8(ascii: "+"), UInt8(ascii: ","),
             UInt8(ascii: ";"), UInt8(ascii: "="):
            return true
        default:
            return false
        }
    }

    private static func isHex(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x46) || (b >= 0x61 && b <= 0x66)
    }
}
