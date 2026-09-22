import Foundation

/// What kind of content a stream URL carries.
public enum StreamKind: String, Sendable, Codable, Hashable, CaseIterable {
    /// A live channel (TV or radio).
    case live
    /// A single on-demand movie.
    case movie
    /// An episode of a series.
    case series

    /// Infers the kind from Xtream-style path conventions (`/movie/…`, `/series/…`); anything else is live.
    public static func infer(from url: URL) -> StreamKind {
        let path = url.path.lowercased()
        if path.hasPrefix("/movie/") || path.contains("/movie/") { return .movie }
        if path.hasPrefix("/series/") || path.contains("/series/") { return .series }
        return .live
    }
}

/// The container/transport format suggested by a stream URL.
///
/// Used to warn users early: CarPlay video only works through AVPlayer (AirPlay video),
/// which plays HLS and MP4-family files but not raw MPEG-TS, MKV, RTSP or UDP.
public enum MediaContainer: String, Sendable, Codable, Hashable, CaseIterable {
    /// HTTP Live Streaming (`.m3u8`).
    case hls
    /// MP4/MOV/M4V.
    case mpeg4
    /// Raw MPEG transport stream (`.ts`) delivered progressively.
    case mpegTS
    /// Audio-only files (`.mp3`, `.aac`, `.m4a`...).
    case audio
    /// Containers AVPlayer cannot play (`.mkv`, `.avi`, `rtsp://`, `udp://`...).
    case unsupported
    /// Nothing can be inferred from the URL; the stream must be probed.
    case unknown

    /// Infers the container from the URL scheme and path extension.
    public static func infer(from url: URL) -> MediaContainer {
        switch url.scheme?.lowercased() {
        case "rtsp", "rtmp", "rtp", "udp", "mms", "srt":
            return .unsupported
        default:
            break
        }
        switch url.pathExtension.lowercased() {
        case "m3u8", "m3u": return .hls
        case "mp4", "m4v", "mov": return .mpeg4
        case "ts", "mts", "m2ts": return .mpegTS
        case "mp3", "aac", "m4a", "ac3", "flac", "wav", "ogg", "opus": return .audio
        case "mkv", "avi", "wmv", "flv", "webm": return .unsupported
        default: return .unknown
        }
    }

    /// Whether AVPlayer is expected to play this container natively.
    public var isAVPlayerCompatible: Bool {
        switch self {
        case .hls, .mpeg4, .audio, .unknown: return true
        case .mpegTS, .unsupported: return false
        }
    }
}
