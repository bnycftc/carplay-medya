import Foundation

/// Errors thrown by CarMediaCore.
///
/// Associated strings never contain credentials: anything that could echo a request URL
/// is passed through ``Redaction`` before it is stored here.
public enum CarMediaError: Error, Sendable, Equatable {
    /// The downloaded content is not a channel list (for example an HLS media playlist or a raw
    /// MPEG-TS/MP4 stream). The app should tell the user "this address is a media stream, not a channel list".
    case notAChannelList(PlaylistKind)
    /// The playlist was parsed but contains no playable entries.
    case emptyPlaylist
    /// The data could not be decoded as text.
    case invalidEncoding
    /// A URL or server address could not be understood. The payload names which one (never the URL itself).
    case invalidURL(String)
    /// The server answered with a non-success HTTP status code.
    case httpStatus(Int)
    /// A network-level failure (timeout, DNS, TLS...). The message is redacted.
    case transport(String)
    /// The server response could not be decoded. The message is redacted.
    case decoding(String)
    /// The Xtream server rejected the username/password.
    case authenticationFailed
    /// The data is gzip-compressed; decompress it before parsing.
    case compressedDataNotSupported
    /// The XMLTV document is malformed and nothing could be recovered.
    case invalidXMLTV(String)
}

extension CarMediaError: LocalizedError {
    /// A short English description. The app is expected to map cases to localized UI strings.
    public var errorDescription: String? {
        switch self {
        case .notAChannelList(let kind):
            switch kind {
            case .hlsMediaPlaylist, .binaryMedia:
                return "This address is a media stream, not a channel list."
            case .channelPlaylist, .unknown:
                return "This address does not contain a channel list."
            }
        case .emptyPlaylist: return "The playlist contains no playable entries."
        case .invalidEncoding: return "The playlist text encoding is not supported."
        case .invalidURL(let what): return "Invalid address: \(what)."
        case .httpStatus(let code): return "The server responded with HTTP \(code)."
        case .transport(let message): return "Network error: \(message)"
        case .decoding(let message): return "Unexpected server response: \(message)"
        case .authenticationFailed: return "The username or password was rejected by the server."
        case .compressedDataNotSupported: return "The data is gzip-compressed and must be decompressed first."
        case .invalidXMLTV(let message): return "Invalid XMLTV guide: \(message)"
        }
    }
}

/// Removes secrets (passwords) from free-form text before it is logged or surfaced.
public enum Redaction {
    /// Placeholder used in place of secrets.
    public static let placeholder = "<redacted>"

    /// Replaces every occurrence of each non-empty secret, raw and percent-encoded, with ``placeholder``.
    public static func redact(_ text: String, secrets: [String]) -> String {
        var result = text
        for secret in secrets where !secret.isEmpty {
            result = result.replacingOccurrences(of: secret, with: placeholder)
            let encoded = PercentEncoding.encodeComponent(secret)
            if encoded != secret {
                result = result.replacingOccurrences(of: encoded, with: placeholder)
            }
        }
        return result
    }
}
