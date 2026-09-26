import Foundation
import CarMediaCore

/// What a pasted link or provider message describes.
public enum DetectedSource: Sendable, Equatable {
    /// An Xtream Codes account (enables movies, series, guide and HLS output).
    case xtream(server: String, username: String, password: String)
    /// A plain M3U playlist address.
    case m3u(url: String)
}

/// Recognizes what the user pasted: an Xtream `get.php` / `player_api.php` link, an Xtream stream URL,
/// a plain M3U address, or a provider message with "server / username / password" lines.
///
/// Providers usually hand out a single `get.php?username=…&password=…` link. Added as an M3U list it
/// loses movies, series, the guide and HLS output, so it is turned into an Xtream account instead.
public enum SourceLinkParser {
    /// Detects the source in `text`, or `nil` when nothing usable is found.
    public static func detect(_ text: String) -> DetectedSource? {
        let fields = keyValueFields(text)
        let url = firstURL(in: text)

        if let url, let xtream = xtreamFromURL(url) {
            return xtream
        }
        let server = fields.server ?? url
        if let server, let username = fields.username, let password = fields.password {
            var base = server.contains("://") ? server : "http://" + server
            if let port = fields.port, let components = URLComponents(string: base), components.port == nil,
               let host = components.host {
                base = (components.scheme ?? "http") + "://" + host + ":" + port
            }
            return .xtream(server: trimTrailingSlash(serverRoot(base)), username: username, password: password)
        }
        if let url { return .m3u(url: url) }
        return nil
    }

    /// Whether an M3U source address is really an Xtream account (offer to convert it).
    public static func xtreamAccount(inM3UAddress url: URL) -> DetectedSource? {
        xtreamFromURL(url.absoluteString)
    }

    // MARK: URLs

    static func xtreamFromURL(_ text: String) -> DetectedSource? {
        guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = components.host, !host.isEmpty else { return nil }
        let origin = scheme + "://" + host + (components.port.map { ":\($0)" } ?? "")
        let segments = components.path.split(separator: "/").map(String.init)

        if let last = segments.last?.lowercased(), ["get.php", "player_api.php", "xmltv.php", "panel_api.php"].contains(last) {
            let items = components.queryItems ?? []
            func value(_ name: String) -> String? {
                items.first { $0.name.lowercased() == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
            }
            guard let user = value("username"), let pass = value("password") else { return nil }
            let prefix = segments.dropLast().joined(separator: "/")
            return .xtream(server: origin + (prefix.isEmpty ? "" : "/" + prefix), username: user, password: pass)
        }

        // …/live|movie|series/{user}/{pass}/{id}.{ext}
        if segments.count >= 4 {
            let kindIndex = segments.count - 4
            let kind = segments[kindIndex].lowercased()
            if ["live", "movie", "series"].contains(kind) {
                let user = segments[kindIndex + 1].removingPercentEncoding ?? segments[kindIndex + 1]
                let pass = segments[kindIndex + 2].removingPercentEncoding ?? segments[kindIndex + 2]
                let prefix = segments[..<kindIndex].joined(separator: "/")
                guard !user.isEmpty, !pass.isEmpty else { return nil }
                return .xtream(server: origin + (prefix.isEmpty ? "" : "/" + prefix), username: user, password: pass)
            }
        }
        return nil
    }

    static func firstURL(in text: String) -> String? {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'<>()[]"))
        for token in text.components(separatedBy: separators) {
            let lower = token.lowercased()
            guard let range = lower.range(of: "http://") ?? lower.range(of: "https://") else { continue }
            let start = token.index(token.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))
            var candidate = String(token[start...])
            while let last = candidate.last, ".,;".contains(last) { candidate.removeLast() }
            if URLComponents(string: candidate)?.host?.isEmpty == false { return candidate }
        }
        return nil
    }

    private static func serverRoot(_ text: String) -> String {
        // "http://host:8080/get.php" typed as a server: keep only the origin.
        guard let components = URLComponents(string: text), let scheme = components.scheme, let host = components.host else {
            return text
        }
        let origin = scheme + "://" + host + (components.port.map { ":\($0)" } ?? "")
        let segments = components.path.split(separator: "/").map(String.init)
        if let last = segments.last?.lowercased(), last.hasSuffix(".php") {
            let prefix = segments.dropLast().joined(separator: "/")
            return origin + (prefix.isEmpty ? "" : "/" + prefix)
        }
        return origin + components.path
    }

    private static func trimTrailingSlash(_ text: String) -> String {
        var result = text
        while result.hasSuffix("/") { result.removeLast() }
        return result
    }

    // MARK: Provider messages

    struct Fields {
        var server: String?
        var username: String?
        var password: String?
        var port: String?
    }

    /// Reads "Key: value" / "Key = value" lines (Turkish and English labels).
    static func keyValueFields(_ text: String) -> Fields {
        var fields = Fields()
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let separator = line.firstIndex(where: { $0 == ":" || $0 == "=" }) else { continue }
            let key = normalizeKey(String(line[..<separator]))
            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !value.isEmpty else { continue }
            switch key {
            case "url", "host", "server", "sunucu", "portal", "dns", "adres", "serverurl", "sunucuadresi", "hosturl":
                if fields.server == nil { fields.server = value.components(separatedBy: .whitespaces).first }
            case "username", "user", "kullaniciadi", "kullanici", "username/email", "login", "kadi":
                if fields.username == nil { fields.username = value }
            case "password", "pass", "sifre", "parola", "pwd":
                if fields.password == nil { fields.password = value }
            case "port":
                if fields.port == nil, value.allSatisfy(\.isNumber) { fields.port = value }
            default:
                break
            }
        }
        return fields
    }

    /// Lowercases, drops spaces/punctuation/emoji and folds Turkish letters: "Kullanıcı Adı" → "kullaniciadi".
    static func normalizeKey(_ key: String) -> String {
        let folded = key.lowercased()
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "i̇", with: "i")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ç", with: "c")
        return String(folded.unicodeScalars.filter { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "/" })
    }
}
