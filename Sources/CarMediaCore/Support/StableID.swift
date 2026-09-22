import Foundation

/// Deterministic identifiers that survive app restarts and re-imports.
///
/// Swift's `Hasher` is randomly seeded per process, so it cannot be used for persisted ids.
/// This uses 64-bit FNV-1a over the UTF-8 bytes of the parts, separated by a unit separator.
public enum StableID {
    /// Returns a 16-character lowercase hex id for the given parts.
    public static func make(_ parts: String...) -> String {
        make(parts)
    }

    /// Returns a 16-character lowercase hex id for the given parts.
    public static func make(_ parts: [String]) -> String {
        let prime: UInt64 = 0x0000_0100_0000_01B3
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for (index, part) in parts.enumerated() {
            if index > 0 {
                hash ^= 0x1F
                hash = hash &* prime
            }
            for byte in part.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* prime
            }
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }
}
