import Foundation

/// What a downloaded "playlist" address actually contains.
public enum PlaylistKind: String, Sendable, Codable, Hashable {
    /// An IPTV channel list (`#EXTM3U` / `#EXTINF` entries, or a plain list of URLs).
    case channelPlaylist
    /// An HLS media or master playlist: a single stream, not a list of channels.
    case hlsMediaPlaylist
    /// Binary media (MPEG-TS, MP4, MP3…): a single stream, not a list of channels.
    case binaryMedia
    /// Anything else (HTML error page, JSON, empty body…).
    case unknown
}

/// Classifies playlist responses so the app can say "this address is a media stream, not a channel list".
public enum PlaylistSniffer {
    /// How many leading bytes are inspected for text markers.
    public static let textSniffLength = 256 * 1024

    /// Classifies `data`, using `contentTypeHeader` only when the bytes are inconclusive.
    ///
    /// Rules, in order:
    /// 1. MP4 `ftyp` box, ID3 tag or MPEG-TS sync pattern (0x47 every 188 bytes) → ``PlaylistKind/binaryMedia``.
    /// 2. `#EXT-X-STREAM-INF` (master), or `#EXTINF` together with `#EXT-X-TARGETDURATION` /
    ///    `#EXT-X-MEDIA-SEQUENCE` (media playlist) → ``PlaylistKind/hlsMediaPlaylist``.
    /// 3. `#EXTM3U` / `#EXTINF`, or lines that are absolute URLs → ``PlaylistKind/channelPlaylist``.
    /// 4. `video/*` or `audio/*` content types (other than `audio/mpegurl` variants) → ``PlaylistKind/binaryMedia``.
    public static func classify(data: Data, contentTypeHeader: String? = nil) -> PlaylistKind {
        if isBinaryMedia(data) { return .binaryMedia }

        let prefix = data.prefix(textSniffLength)
        let text = TextDecoding.stripBOM(String(decoding: prefix, as: UTF8.self))
        let hasExtinf = text.contains("#EXTINF")
        if text.contains("#EXT-X-STREAM-INF") { return .hlsMediaPlaylist }
        if hasExtinf, text.contains("#EXT-X-TARGETDURATION") || text.contains("#EXT-X-MEDIA-SEQUENCE") {
            return .hlsMediaPlaylist
        }
        let trimmed = text.drop(while: { $0.isWhitespace })
        if trimmed.hasPrefix("#EXTM3U") || hasExtinf { return .channelPlaylist }
        if looksLikeURLList(trimmed) { return .channelPlaylist }

        if let type = contentTypeHeader?.lowercased() {
            let isPlaylistType = type.contains("mpegurl")
            if !isPlaylistType, type.hasPrefix("video/") || type.hasPrefix("audio/") {
                return .binaryMedia
            }
        }
        return .unknown
    }

    /// Detects MP4/MOV (`ftyp`), MP3 with an ID3 tag, and MPEG-TS (sync byte 0x47 repeating every 188 bytes).
    static func isBinaryMedia(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(1024))
        if bytes.count >= 8, bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
            return true // "ftyp"
        }
        if bytes.count >= 3, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 {
            return true // "ID3"
        }
        let packet = 188
        guard bytes.count > packet else { return false }
        let requiredSyncs = bytes.count > 2 * packet ? 3 : 2
        for offset in 0..<min(packet, bytes.count) {
            var syncs = 0
            var position = offset
            while position < bytes.count, bytes[position] == 0x47 {
                syncs += 1
                if syncs >= requiredSyncs { return true }
                position += packet
            }
        }
        return false
    }

    private static func looksLikeURLList(_ text: Substring) -> Bool {
        var checked = 0
        var urls = 0
        for line in text.split(whereSeparator: \.isNewline).prefix(20) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            checked += 1
            let lower = trimmed.lowercased()
            if ["http://", "https://", "rtmp://", "rtsp://", "udp://"].contains(where: { lower.hasPrefix($0) }) {
                urls += 1
            }
        }
        return checked > 0 && urls * 2 >= checked
    }
}
