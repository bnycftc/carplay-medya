import Foundation

/// Byte-level parsing of `key="value" key2=value2,Title` attribute lists.
///
/// Works on UTF-8 bytes: every delimiter is ASCII, so multi-byte characters are never split.
public enum M3UAttributeParser {
    /// Result of parsing an attribute list.
    public struct Result: Sendable, Equatable {
        /// Attributes, keys lowercased. The first occurrence of a key wins.
        public var attributes: [String: String]
        /// Text after the first unquoted comma (untrimmed), or `nil` when there is no comma.
        public var trailingText: String?
    }

    /// Parses attributes from a string (convenience for tests and callers holding text).
    public static func parse(_ text: String, stopAtComma: Bool = true) -> Result {
        let bytes = Array(text.utf8)
        return parse(bytes[...], stopAtComma: stopAtComma)
    }

    /// Parses attributes from UTF-8 bytes.
    ///
    /// - Quoted values (`"…"` or `'…'`) may contain spaces and commas.
    /// - Unquoted values end at whitespace or (when `stopAtComma`) a comma.
    /// - An unterminated quote falls back to ending the value at the next comma.
    /// - Bare tokens without `=` are ignored.
    static func parse(_ s: ArraySlice<UInt8>, stopAtComma: Bool) -> Result {
        var attributes: [String: String] = [:]
        var i = s.startIndex
        let end = s.endIndex
        let comma = UInt8(ascii: ",")
        let equals = UInt8(ascii: "=")

        while i < end {
            while i < end, ByteText.isSpace(s[i]) { i += 1 }
            guard i < end else { break }
            if stopAtComma, s[i] == comma {
                return Result(attributes: attributes, trailingText: ByteText.string(s[(i + 1)...]))
            }
            let keyStart = i
            while i < end, s[i] != equals, !ByteText.isSpace(s[i]), !(stopAtComma && s[i] == comma) { i += 1 }
            let keyEnd = i
            guard i < end, s[i] == equals else { continue }
            i += 1 // skip '='

            var valueSlice: ArraySlice<UInt8>
            if i < end, s[i] == UInt8(ascii: "\"") || s[i] == UInt8(ascii: "'") {
                let quote = s[i]
                let valueStart = i + 1
                var j = valueStart
                while j < end, s[j] != quote { j += 1 }
                if j < end {
                    valueSlice = s[valueStart..<j]
                    i = j + 1
                } else {
                    // Unterminated quote: end the value at the next comma (or line end).
                    var k = valueStart
                    while k < end, !(stopAtComma && s[k] == comma) { k += 1 }
                    valueSlice = s[valueStart..<k]
                    i = k
                }
            } else {
                let valueStart = i
                while i < end, !ByteText.isSpace(s[i]), !(stopAtComma && s[i] == comma) { i += 1 }
                valueSlice = s[valueStart..<i]
            }

            if keyEnd > keyStart {
                let key = ByteText.string(s[keyStart..<keyEnd]).lowercased()
                if attributes[key] == nil {
                    attributes[key] = ByteText.string(ByteText.trim(valueSlice))
                }
            }
        }
        return Result(attributes: attributes, trailingText: nil)
    }
}

/// Small helpers for ASCII-delimited UTF-8 byte slices.
enum ByteText {
    @inline(__always)
    static func isSpace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0B || b == 0x0C
    }

    static func trim(_ s: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        var start = s.startIndex
        var end = s.endIndex
        while start < end, isSpace(s[start]) { start += 1 }
        while end > start, isSpace(s[end - 1]) { end -= 1 }
        return s[start..<end]
    }

    static func string(_ s: ArraySlice<UInt8>) -> String {
        String(decoding: s, as: UTF8.self)
    }

    /// ASCII case-insensitive prefix test; `prefix` must be uppercase ASCII.
    static func hasPrefix(_ s: ArraySlice<UInt8>, _ prefix: [UInt8]) -> Bool {
        guard s.count >= prefix.count else { return false }
        var i = s.startIndex
        for p in prefix {
            var b = s[i]
            if b >= 0x61 && b <= 0x7A { b -= 0x20 }
            if b != p { return false }
            i += 1
        }
        return true
    }

    /// Splits `key=value` at the first `=`; key lowercased and both sides trimmed.
    static func keyValue(_ s: ArraySlice<UInt8>) -> (String, String)? {
        guard let eq = s.firstIndex(of: UInt8(ascii: "=")) else { return nil }
        let key = string(trim(s[s.startIndex..<eq])).lowercased()
        guard !key.isEmpty else { return nil }
        return (key, string(trim(s[(eq + 1)...])))
    }
}
