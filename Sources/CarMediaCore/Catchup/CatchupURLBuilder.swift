import Foundation

/// Builds archive ("catch-up" / timeshift) URLs for past programmes of a live channel.
///
/// Supported modes, taken from the channel's `catchup` attribute:
/// - `xc`: Xtream Codes timeshift, `/timeshift/{user}/{pass}/{minutes}/{yyyy-MM-dd:HH-mm}/{id}.m3u8`
///   (HLS, because AVPlayer cannot play the `.ts` variant). The start time is written in the
///   server's time zone.
/// - `default`: `catchup-source` is a complete URL template.
/// - `append`: `catchup-source` is appended to the stream URL.
/// - `shift` / `timeshift`: `utc={start}&lutc={now}` is appended to the stream URL's query.
/// - `flussonic` / `flussonic-hls` / `fs`: the playlist name becomes `{name}-{start}-{duration}.m3u8`.
///
/// Template placeholders: `{utc}` `${start}` (start, Unix seconds), `{utcend}` `${end}`,
/// `{lutc}` `${now}` `${timestamp}`, `{duration}` `${duration}` (seconds), `{offset}` `${offset}`
/// (seconds since start), `{Y} {m} {d} {H} {M} {S}` (start in the given time zone) and
/// `{utc:FORMAT}` / `${start:FORMAT}` / `{utcend:FORMAT}` / `${end:FORMAT}` where FORMAT uses
/// `Y m d H M S` letters.
///
/// Returned URLs may contain Xtream credentials (like every Xtream stream URL); never log them.
public enum CatchupURLBuilder {
    /// Archive depth assumed when the source does not state one (`catchup-days`).
    public static let defaultArchiveDays = 7

    /// Whether `channel` announces an archive this builder understands.
    public static func supportsCatchup(_ channel: Channel) -> Bool {
        guard let mode = mode(of: channel) else { return false }
        switch mode {
        case "default", "append":
            return !(channel.catchupSource ?? "").isEmpty
        default:
            return true
        }
    }

    /// Whether a programme that started at `start` can be replayed from the archive at `now`.
    public static func isAvailable(for channel: Channel, programmeStart start: Date, programmeEnd end: Date, now: Date = Date()) -> Bool {
        guard supportsCatchup(channel), start < now, end > start else { return false }
        let days = archiveDays(of: channel)
        return start >= now.addingTimeInterval(-Double(days) * 86_400)
    }

    /// Archive depth from the `catchup-days` attribute (defaults to ``defaultArchiveDays``).
    public static func archiveDays(of channel: Channel) -> Int {
        if let raw = channel.attributes["catchup-days"], let days = Int(raw.trimmingCharacters(in: .whitespaces)), days > 0 {
            return days
        }
        return defaultArchiveDays
    }

    /// The archive URL for the programme `start..<end`, or `nil` if the channel has no usable archive.
    /// - Parameter timeZone: time zone for date placeholders and Xtream start times (Xtream servers
    ///   expect their own local time; pass `server_info.timezone` when known).
    public static func url(
        for channel: Channel,
        start: Date,
        end: Date,
        now: Date = Date(),
        timeZone: TimeZone = TimeZone(identifier: "UTC")!
    ) -> URL? {
        guard end > start, let mode = mode(of: channel) else { return nil }
        let context = Context(start: start, end: end, now: now, timeZone: timeZone)
        switch mode {
        case "xc":
            return xtreamTimeshiftURL(streamURL: channel.streamURL, context: context)
        case "default":
            guard let template = channel.catchupSource, !template.isEmpty else { return nil }
            return PercentEncoding.lenientURL(substitute(template, context: context), relativeTo: channel.streamURL)
        case "append":
            guard let template = channel.catchupSource, !template.isEmpty else { return nil }
            return PercentEncoding.lenientURL(channel.streamURL.absoluteString + substitute(template, context: context))
        case "shift", "timeshift":
            let base = channel.streamURL.absoluteString
            let separator = base.contains("?") ? "&" : "?"
            return URL(string: base + separator + "utc=\(context.startUnix)&lutc=\(context.nowUnix)")
        case "flussonic", "flussonic-hls", "fs":
            return flussonicURL(streamURL: channel.streamURL, context: context)
        default:
            return nil
        }
    }

    // MARK: Modes

    /// The normalized catch-up mode (`xc`, `default`, `append`, `shift`, `timeshift`, `flussonic`…), or `nil`.
    public static func mode(of channel: Channel) -> String? {
        guard let raw = channel.catchup?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "xc", "default", "append", "shift", "timeshift", "flussonic", "flussonic-hls", "fs":
            return raw
        default:
            return nil
        }
    }

    /// `/live/{u}/{p}/{id}.{ext}` → `/timeshift/{u}/{p}/{minutes}/{start}/{id}.m3u8`, keeping any path prefix.
    static func xtreamTimeshiftURL(streamURL: URL, context: Context) -> URL? {
        guard var components = URLComponents(url: streamURL, resolvingAgainstBaseURL: false) else { return nil }
        var parts = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        // ["", …prefix, "live", user, pass, "id.ext"]
        guard parts.count >= 5, parts[parts.count - 4].lowercased() == "live" else { return nil }
        let file = parts[parts.count - 1]
        let streamID = file.split(separator: ".").first.map(String.init) ?? file
        guard !streamID.isEmpty else { return nil }
        let user = parts[parts.count - 3]
        let pass = parts[parts.count - 2]
        let minutes = max(1, Int((context.duration / 60).rounded(.up)))
        let startText = format("Y-m-d:H-M", date: context.start, timeZone: context.timeZone)
        parts.removeLast(4)
        parts += ["timeshift", user, pass, String(minutes), startText, streamID + ".m3u8"]
        components.percentEncodedPath = parts.joined(separator: "/")
        components.percentEncodedQuery = nil
        return components.url
    }

    /// Replaces the playlist name: `…/index.m3u8` → `…/index-{start}-{duration}.m3u8`.
    static func flussonicURL(streamURL: URL, context: Context) -> URL? {
        guard var components = URLComponents(url: streamURL, resolvingAgainstBaseURL: false) else { return nil }
        let path = components.percentEncodedPath
        guard let slash = path.lastIndex(of: "/") else { return nil }
        let file = String(path[path.index(after: slash)...])
        let lower = file.lowercased()
        guard lower.hasSuffix(".m3u8") else { return nil }
        let name = String(file.dropLast(5))
        let base = name.isEmpty ? "index" : name
        let seconds = max(1, Int(context.duration.rounded()))
        components.percentEncodedPath = String(path[...slash]) + "\(base)-\(context.startUnix)-\(seconds).m3u8"
        return components.url
    }

    // MARK: Templates

    struct Context {
        var start: Date
        var end: Date
        var now: Date
        var timeZone: TimeZone

        var startUnix: Int { Int(start.timeIntervalSince1970) }
        var endUnix: Int { Int(end.timeIntervalSince1970) }
        var nowUnix: Int { Int(now.timeIntervalSince1970) }
        var duration: TimeInterval { end.timeIntervalSince(start) }
        var offset: Int { max(0, Int(now.timeIntervalSince(start))) }
    }

    static func substitute(_ template: String, context: Context) -> String {
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            let isDollar = character == "$" && template.index(after: index) < template.endIndex
                && template[template.index(after: index)] == "{"
            if character == "{" || isDollar {
                let open = isDollar ? template.index(after: index) : index
                if let close = template[open...].firstIndex(of: "}") {
                    let token = String(template[template.index(after: open)..<close])
                    if let value = value(for: token, context: context) {
                        result += value
                        index = template.index(after: close)
                        continue
                    }
                }
            }
            result.append(character)
            index = template.index(after: index)
        }
        return result
    }

    private static func value(for token: String, context: Context) -> String? {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        let name = parts[0].lowercased()
        if parts.count == 2 {
            switch name {
            case "utc", "start": return format(parts[1], date: context.start, timeZone: context.timeZone)
            case "utcend", "end": return format(parts[1], date: context.end, timeZone: context.timeZone)
            case "lutc", "now", "timestamp": return format(parts[1], date: context.now, timeZone: context.timeZone)
            default: return nil
            }
        }
        switch parts[0] {
        case "Y", "m", "d", "H", "M", "S":
            return format(parts[0], date: context.start, timeZone: context.timeZone)
        default:
            break
        }
        switch name {
        case "utc", "start": return String(context.startUnix)
        case "utcend", "end": return String(context.endUnix)
        case "lutc", "now", "timestamp": return String(context.nowUnix)
        case "duration": return String(Int(context.duration.rounded()))
        case "offset": return String(context.offset)
        default: return nil
        }
    }

    /// Formats `date` with `Y m d H M S` letters (zero-padded); other characters are copied.
    static func format(_ pattern: String, date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?) -> String {
            let v = value ?? 0
            return v < 10 ? "0\(v)" : String(v)
        }
        var out = ""
        for character in pattern {
            switch character {
            case "Y": out += String(c.year ?? 0)
            case "m": out += pad(c.month)
            case "d": out += pad(c.day)
            case "H": out += pad(c.hour)
            case "M": out += pad(c.minute)
            case "S": out += pad(c.second)
            default: out.append(character)
            }
        }
        return out
    }
}
