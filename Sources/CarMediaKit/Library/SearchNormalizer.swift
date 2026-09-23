import Foundation

/// Case-, diacritic- and Turkish-dotted/dotless-i-insensitive text matching for channel search.
public enum SearchNormalizer {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Lowercased, diacritic-free form of `text` (`İ`, `I`, `ı` and `i` all become `i`).
    public static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{0130}", with: "i") // İ
            .replacingOccurrences(of: "\u{0131}", with: "i") // ı
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: posix)
    }

    /// Normalized, non-empty whitespace-separated tokens of a query.
    public static func tokens(_ query: String) -> [String] {
        normalize(query)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    /// `true` if every token occurs in the (already normalized) `key`. No tokens matches everything.
    public static func matches(normalizedKey key: String, tokens: [String]) -> Bool {
        tokens.allSatisfy { key.contains($0) }
    }
}
