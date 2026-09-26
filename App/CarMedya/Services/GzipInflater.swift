import CarMediaCore
import Foundation

/// Inflates gzip files (e.g. `guide.xml.gz`) with the system's raw-DEFLATE decoder.
///
/// `CarMediaCore.Gzip` strips the gzip framing; `NSData.decompressed(using: .zlib)` expects raw DEFLATE.
enum GzipInflater {
    static func inflate(_ data: Data) throws -> Data {
        let member = try Gzip.member(of: data)
        let inflated = try (member.deflate as NSData).decompressed(using: .zlib) as Data
        // ISIZE is the length modulo 2^32; only a mismatch for small files indicates corruption.
        if inflated.count < Int(UInt32.max), UInt32(inflated.count) != member.uncompressedSize {
            throw CarMediaError.compressedDataNotSupported
        }
        return inflated
    }
}
