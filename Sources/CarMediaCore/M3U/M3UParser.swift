import Foundation

/// Parses user-supplied M3U / M3U8 channel lists ("extended M3U", IPTV flavour).
///
/// Supported syntax:
/// - optional `#EXTM3U` header with attributes (`url-tvg`, `x-tvg-url`, …)
/// - `#EXTINF:<duration> [attrs],<title>` with quoted/unquoted attributes and commas in titles
/// - `#EXTGRP:`, `#EXTVLCOPT:key=value`, `#KODIPROP:key=value`
/// - Kodi-style header suffixes: `http://host/stream.m3u8|User-Agent=X&Referer=Y`
/// - comments, blank lines, CRLF/LF/CR line endings, UTF-8 BOM, trailing whitespace
/// - URLs containing spaces or non-ASCII characters (percent-encoded)
///
/// HLS media/master playlists (`#EXT-X-TARGETDURATION`, `#EXT-X-STREAM-INF`, …) are rejected
/// with ``CarMediaError/notAChannelList(_:)`` because they are streams, not channel lists.
public struct M3UParser: Sendable {
    /// Creates a parser.
    public init() {}

    /// Parses raw bytes (any supported text encoding).
    ///
    /// - Parameter baseURL: resolves relative entry URLs (usually the playlist's own URL).
    /// - Throws: ``CarMediaError/notAChannelList(_:)``, ``CarMediaError/emptyPlaylist``,
    ///   ``CarMediaError/invalidEncoding``, ``CarMediaError/compressedDataNotSupported``.
    public func parse(data: Data, baseURL: URL? = nil) throws -> Playlist {
        if TextDecoding.isGzip(data) { throw CarMediaError.compressedDataNotSupported }
        switch PlaylistSniffer.classify(data: data) {
        case .hlsMediaPlaylist: throw CarMediaError.notAChannelList(.hlsMediaPlaylist)
        case .binaryMedia: throw CarMediaError.notAChannelList(.binaryMedia)
        case .channelPlaylist, .unknown: break
        }
        guard let text = TextDecoding.string(from: data) else { throw CarMediaError.invalidEncoding }
        return try parse(string: text, baseURL: baseURL)
    }

    /// Parses playlist text.
    public func parse(string: String, baseURL: URL? = nil) throws -> Playlist {
        let raw = scan(Array(TextDecoding.stripBOM(string).utf8))
        if raw.hasStreamInf || (raw.hasSegmentMarkers && raw.sawExtinf) {
            throw CarMediaError.notAChannelList(.hlsMediaPlaylist)
        }
        var skipped = 0
        var seenIDs: [String: Int] = [:]
        var channels: [Channel] = []
        channels.reserveCapacity(raw.entries.count)
        for entry in raw.entries {
            guard var channel = makeChannel(from: entry, baseURL: baseURL) else {
                skipped += 1
                continue
            }
            // Identical url+title pairs get a deterministic occurrence suffix so ids stay unique.
            let occurrence = (seenIDs[channel.id] ?? 0) + 1
            seenIDs[channel.id] = occurrence
            if occurrence > 1 { channel.id += "-\(occurrence)" }
            channels.append(channel)
        }
        guard !channels.isEmpty else { throw CarMediaError.emptyPlaylist }
        return Playlist(
            channels: channels,
            headerAttributes: raw.header,
            epgURLs: Self.epgURLs(from: raw.header),
            skippedEntryCount: skipped
        )
    }

    /// Returns the raw entries without building channels (no HLS or emptiness checks).
    public func entries(in string: String) -> (header: [String: String], entries: [M3UEntry]) {
        let raw = scan(Array(TextDecoding.stripBOM(string).utf8))
        return (raw.header, raw.entries)
    }

    // MARK: - Scanning

    struct RawScan {
        var header: [String: String] = [:]
        var entries: [M3UEntry] = []
        var sawExtinf = false
        var hasSegmentMarkers = false
        var hasStreamInf = false
    }

    private static let extinf = Array("#EXTINF:".utf8)
    private static let extm3u = Array("#EXTM3U".utf8)
    private static let extgrp = Array("#EXTGRP:".utf8)
    private static let extvlcopt = Array("#EXTVLCOPT:".utf8)
    private static let kodiprop = Array("#KODIPROP:".utf8)
    private static let extTargetDuration = Array("#EXT-X-TARGETDURATION".utf8)
    private static let extMediaSequence = Array("#EXT-X-MEDIA-SEQUENCE".utf8)
    private static let extStreamInf = Array("#EXT-X-STREAM-INF".utf8)

    func scan(_ bytes: [UInt8]) -> RawScan {
        var result = RawScan()
        var pendingInfo: (duration: Double?, title: String?, attributes: [String: String])?
        var pendingGroup: String?
        var pendingVLC: [String: String] = [:]
        var pendingKodi: [String: String] = [:]

        let n = bytes.count
        var i = 0
        var lineNumber = 0
        while i < n {
            var j = i
            while j < n, bytes[j] != 0x0A, bytes[j] != 0x0D { j += 1 }
            let line = ByteText.trim(bytes[i..<j])
            lineNumber += 1
            i = (j + 1 < n && bytes[j] == 0x0D && bytes[j + 1] == 0x0A) ? j + 2 : j + 1
            guard let first = line.first else { continue }

            if first == UInt8(ascii: "#") {
                if ByteText.hasPrefix(line, Self.extinf) {
                    result.sawExtinf = true
                    pendingInfo = Self.parseExtinf(line.dropFirst(Self.extinf.count))
                } else if ByteText.hasPrefix(line, Self.extm3u) {
                    let attrs = M3UAttributeParser.parse(line.dropFirst(Self.extm3u.count), stopAtComma: false)
                    result.header.merge(attrs.attributes) { current, _ in current }
                } else if ByteText.hasPrefix(line, Self.extgrp) {
                    let value = ByteText.string(ByteText.trim(line.dropFirst(Self.extgrp.count)))
                    pendingGroup = value.isEmpty ? nil : value
                } else if ByteText.hasPrefix(line, Self.extvlcopt) {
                    if let kv = ByteText.keyValue(line.dropFirst(Self.extvlcopt.count)) { pendingVLC[kv.0] = kv.1 }
                } else if ByteText.hasPrefix(line, Self.kodiprop) {
                    if let kv = ByteText.keyValue(line.dropFirst(Self.kodiprop.count)) { pendingKodi[kv.0] = kv.1 }
                } else if ByteText.hasPrefix(line, Self.extTargetDuration) || ByteText.hasPrefix(line, Self.extMediaSequence) {
                    result.hasSegmentMarkers = true
                } else if ByteText.hasPrefix(line, Self.extStreamInf) {
                    result.hasStreamInf = true
                }
                // Anything else starting with '#' is a comment or an unsupported directive.
                continue
            }

            // URL line: finalize the pending entry.
            var urlPart = line
            var pipeHeaders: [String: String] = [:]
            if let pipe = line.firstIndex(of: UInt8(ascii: "|")) {
                urlPart = ByteText.trim(line[line.startIndex..<pipe])
                for pair in line[(pipe + 1)...].split(separator: UInt8(ascii: "&")) {
                    if let kv = ByteText.keyValue(pair) { pipeHeaders[kv.0] = kv.1 }
                }
            }
            result.entries.append(M3UEntry(
                duration: pendingInfo?.duration,
                title: pendingInfo?.title,
                attributes: pendingInfo?.attributes ?? [:],
                urlString: ByteText.string(urlPart),
                extGroup: pendingGroup,
                vlcOptions: pendingVLC,
                kodiProperties: pendingKodi,
                pipeHeaders: pipeHeaders,
                lineNumber: lineNumber
            ))
            pendingInfo = nil
            pendingGroup = nil
            pendingVLC = [:]
            pendingKodi = [:]
        }
        return result
    }

    /// Parses the part of an `#EXTINF:` line after the colon.
    static func parseExtinf(_ body: ArraySlice<UInt8>) -> (duration: Double?, title: String?, attributes: [String: String]) {
        var i = body.startIndex
        while i < body.endIndex, ByteText.isSpace(body[i]) { i += 1 }
        let durationStart = i
        while i < body.endIndex, !ByteText.isSpace(body[i]), body[i] != UInt8(ascii: ",") { i += 1 }
        let duration = Double(ByteText.string(body[durationStart..<i]))
        let parsed = M3UAttributeParser.parse(body[i...], stopAtComma: true)
        let title = parsed.trailingText?.trimmingCharacters(in: .whitespaces)
        return (duration, (title?.isEmpty ?? true) ? nil : title, parsed.attributes)
    }

    // MARK: - Channel building

    func makeChannel(from entry: M3UEntry, baseURL: URL?) -> Channel? {
        guard let url = PercentEncoding.lenientURL(entry.urlString, relativeTo: baseURL) else { return nil }
        let attrs = entry.attributes
        func attr(_ key: String) -> String? {
            guard let value = attrs[key], !value.isEmpty else { return nil }
            return value
        }
        let title = entry.title ?? attr("tvg-name") ?? Self.fallbackTitle(for: url)
        let group = attr("group-title") ?? entry.extGroup
        let userAgent = entry.vlcOptions["http-user-agent"] ?? entry.pipeHeaders["user-agent"] ?? attr("user-agent")
        let referrer = entry.vlcOptions["http-referrer"] ?? entry.vlcOptions["http-referer"]
            ?? entry.pipeHeaders["referer"] ?? entry.pipeHeaders["referrer"]
        return Channel(
            id: Channel.stableID(url: url, title: title),
            title: title,
            streamURL: url,
            kind: StreamKind.infer(from: url),
            groupTitle: group,
            tvgID: attr("tvg-id"),
            tvgName: attr("tvg-name"),
            logo: attr("tvg-logo"),
            channelNumber: attr("tvg-chno").flatMap { Int($0) },
            language: attr("tvg-language"),
            country: attr("tvg-country"),
            catchup: attr("catchup"),
            catchupSource: attr("catchup-source"),
            duration: entry.duration,
            isRadio: attr("radio")?.lowercased() == "true",
            userAgent: userAgent,
            referrer: referrer,
            vlcOptions: entry.vlcOptions,
            kodiProperties: entry.kodiProperties,
            attributes: attrs
        )
    }

    static func fallbackTitle(for url: URL) -> String {
        let last = url.deletingPathExtension().lastPathComponent
        if !last.isEmpty, last != "/" { return last }
        return url.host ?? url.absoluteString
    }

    static func epgURLs(from header: [String: String]) -> [URL] {
        var urls: [URL] = []
        for key in ["url-tvg", "x-tvg-url", "tvg-url"] {
            guard let value = header[key] else { continue }
            for part in value.split(separator: ",") {
                if let url = PercentEncoding.lenientURL(String(part)), !urls.contains(url) {
                    urls.append(url)
                }
            }
        }
        return urls
    }
}
