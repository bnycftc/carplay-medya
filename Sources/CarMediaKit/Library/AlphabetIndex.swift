import Foundation
import CarMediaCore

/// Channels grouped by the first letter of their name, for the CarPlay "A–Z" tab.
public struct AlphabetBucket: Sendable, Hashable, Identifiable {
    /// Display key: `A`…`Z`, `0–9` or `#`.
    public var letter: String
    /// Channels in name order.
    public var channels: [Channel]

    /// The letter.
    public var id: String { letter }
}

/// Builds A–Z buckets. Letters are folded like search (`Ç` → `C`, `İ`/`ı` → `I`, `Ş` → `S`…) so a
/// driver finds "Şimdi TV" under S, the letter shown on most car keyboards and lists.
public enum AlphabetIndex {
    /// Key for digits.
    public static let digitsKey = "0\u{2013}9"
    /// Key for anything else (symbols, other scripts).
    public static let otherKey = "#"

    /// Bucket key of a title.
    public static func key(for title: String) -> String {
        let normalized = SearchNormalizer.normalize(title.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let first = normalized.unicodeScalars.first(where: { !CharacterSet.punctuationCharacters.contains($0) }) else {
            return otherKey
        }
        if first.isASCII, CharacterSet.decimalDigits.contains(first) { return digitsKey }
        if first.isASCII, CharacterSet.letters.contains(first) { return String(first).uppercased() }
        return otherKey
    }

    /// Buckets in A…Z order, then `0–9`, then `#`; channels sorted by name inside each bucket.
    /// Empty buckets are omitted.
    public static func buckets(_ channels: [Channel]) -> [AlphabetBucket] {
        var grouped: [String: [(key: String, channel: Channel)]] = [:]
        for channel in channels {
            grouped[key(for: channel.title), default: []].append((SearchNormalizer.normalize(channel.title), channel))
        }
        return grouped.keys.sorted(by: order).map { letter in
            let sorted = (grouped[letter] ?? []).sorted { $0.key < $1.key }
            return AlphabetBucket(letter: letter, channels: sorted.map(\.channel))
        }
    }

    private static func order(_ lhs: String, _ rhs: String) -> Bool {
        func rank(_ key: String) -> Int {
            switch key {
            case digitsKey: return 1
            case otherKey: return 2
            default: return 0
            }
        }
        let (a, b) = (rank(lhs), rank(rhs))
        return a != b ? a < b : lhs < rhs
    }
}

extension LibraryState {
    /// Channels of visible (not hidden) groups, in library order, without duplicates.
    public var visibleChannels: [Channel] {
        var seen = Set<String>()
        var result: [Channel] = []
        for group in visibleGroups {
            for channel in channels(in: group) where seen.insert(channel.id).inserted {
                result.append(channel)
            }
        }
        return result
    }
}
