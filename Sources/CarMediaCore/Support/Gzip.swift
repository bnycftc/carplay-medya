import Foundation

/// Gzip (RFC 1952) container parsing without decompression.
///
/// Foundation has no portable inflater, so the package only strips the gzip framing and returns the raw
/// DEFLATE stream; the app inflates it with a platform API (`NSData.decompressed(using: .zlib)`, which
/// expects raw DEFLATE). This keeps the package Foundation-only and testable on every platform.
public enum Gzip {
    /// The raw DEFLATE payload of the first gzip member and the uncompressed size from its trailer.
    public struct Member: Sendable, Equatable {
        /// Raw DEFLATE bytes (no header, no trailer).
        public var deflate: Data
        /// `ISIZE`: uncompressed length modulo 2³².
        public var uncompressedSize: UInt32
    }

    /// Parses the gzip header and trailer.
    /// - Throws: ``CarMediaError/compressedDataNotSupported`` for data that is not a valid gzip member.
    public static func member(of data: Data) throws -> Member {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else {
            throw CarMediaError.compressedDataNotSupported
        }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard index + 2 <= bytes.count else { throw CarMediaError.compressedDataNotSupported }
            let length = Int(bytes[index]) | Int(bytes[index + 1]) << 8
            index += 2 + length
        }
        if flags & 0x08 != 0 { index = try skipZeroTerminated(bytes, from: index) } // FNAME
        if flags & 0x10 != 0 { index = try skipZeroTerminated(bytes, from: index) } // FCOMMENT
        if flags & 0x02 != 0 { index += 2 } // FHCRC
        let trailerStart = bytes.count - 8
        guard index <= trailerStart else { throw CarMediaError.compressedDataNotSupported }
        let size = UInt32(bytes[trailerStart + 4])
            | UInt32(bytes[trailerStart + 5]) << 8
            | UInt32(bytes[trailerStart + 6]) << 16
            | UInt32(bytes[trailerStart + 7]) << 24
        return Member(deflate: Data(bytes[index..<trailerStart]), uncompressedSize: size)
    }

    private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) throws -> Int {
        var index = start
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        guard index < bytes.count else { throw CarMediaError.compressedDataNotSupported }
        return index + 1
    }
}
