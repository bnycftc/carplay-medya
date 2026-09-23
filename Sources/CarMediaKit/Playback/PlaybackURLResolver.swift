import Foundation
import CarMediaCore

/// What to hand to AVPlayer for a channel.
public struct PlaybackRequest: Sendable, Hashable {
    /// URL to open.
    public var url: URL
    /// Required `User-Agent`, if any (AVFoundation has a public option for it).
    public var userAgent: String?
    /// Required `Referer`, if any. AVFoundation has no public option for arbitrary headers, so the app
    /// cannot send it; kept so the UI can warn that the stream may refuse playback.
    public var referrer: String?
    /// `true` for live streams (no duration, no seeking).
    public var isLive: Bool
    /// `true` for radio / audio-only content.
    public var isAudioOnly: Bool
}

/// Outcome of resolving a channel.
public enum PlaybackResolution: Sendable, Hashable {
    /// Playable with AVPlayer.
    case playable(PlaybackRequest)
    /// Cannot be played; tell the user why (never silently fail).
    case unsupported(UnsupportedReason)
}

/// Turns a ``Channel`` into something AVPlayer can open.
///
/// Rules (CLAUDE.md red lines): HLS/MP4/audio are played; Xtream live `.ts` is rewritten to `.m3u8`
/// (the panel serves both); MKV, RTSP/RTMP, UDP and raw TS elsewhere are reported as unsupported.
public struct PlaybackURLResolver: Sendable {
    /// Also rewrite Xtream-style `/live/{user}/{pass}/{id}.ts` paths found in plain M3U lists
    /// (lists exported by Xtream panels with `output=ts`). Off by default: other servers may not
    /// offer an `.m3u8` twin.
    public var rewriteXtreamStylePathsInM3U: Bool

    /// Creates a resolver.
    public init(rewriteXtreamStylePathsInM3U: Bool = false) {
        self.rewriteXtreamStylePathsInM3U = rewriteXtreamStylePathsInM3U
    }

    /// Resolves `channel`.
    /// - Parameter isXtreamSource: `true` when the channel came from an Xtream account.
    public func resolve(_ channel: Channel, isXtreamSource: Bool) -> PlaybackResolution {
        var url = channel.streamURL
        switch url.scheme?.lowercased() {
        case "http"?, "https"?, "file"?:
            break
        case "rtsp"?, "rtsps"?, "rtmp"?, "rtmps"?, "rtp"?:
            return .unsupported(.rtsp)
        case "udp"?:
            return .unsupported(.udp)
        default:
            return .unsupported(.otherProtocol)
        }

        switch url.pathExtension.lowercased() {
        case "mkv":
            return .unsupported(.matroska)
        case "avi", "wmv", "flv", "webm":
            return .unsupported(.container)
        case "ts", "mts", "m2ts":
            let rewrite = channel.kind == .live
                && (isXtreamSource || (rewriteXtreamStylePathsInM3U && Self.isXtreamLivePath(url)))
            guard rewrite, let hls = Self.replacingExtension(of: url, with: "m3u8") else {
                return .unsupported(.rawTransportStream)
            }
            url = hls
        default:
            break
        }

        let container = MediaContainer.infer(from: url)
        let isLive = channel.kind == .live && !(channel.duration.map { $0 > 0 } ?? false)
        return .playable(PlaybackRequest(
            url: url,
            userAgent: channel.userAgent,
            referrer: channel.referrer,
            isLive: isLive,
            isAudioOnly: channel.isRadio || container == .audio
        ))
    }

    /// `/live/{user}/{pass}/{id}.ts` (optionally below a path prefix).
    static func isXtreamLivePath(_ url: URL) -> Bool {
        let parts = url.path.split(separator: "/")
        guard parts.count >= 4 else { return false }
        return parts[parts.count - 4].lowercased() == "live"
    }

    /// Replaces the path extension without touching the rest of the URL (credentials in the path stay encoded).
    static func replacingExtension(of url: URL, with newExtension: String) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = components.percentEncodedPath
        guard let dot = path.lastIndex(of: "."), !path[dot...].contains("/") else { return nil }
        components.percentEncodedPath = String(path[..<dot]) + "." + newExtension
        return components.url
    }
}
