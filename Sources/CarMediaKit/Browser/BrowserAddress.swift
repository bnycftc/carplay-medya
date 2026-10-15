import Foundation

/// Turns what the user types in the phone browser into a web address. Pure logic; the app opens the result
/// in `SFSafariViewController`, which accepts only http(s) URLs.
public enum BrowserAddress {
    /// Turns what the user typed into a web URL: a full http(s) URL is kept; something that looks like a host
    /// ("example.com", "example.com/path", "sub.example.com:8080") gets "https://"; anything else becomes a
    /// search using `searchTemplate`, where "%@" is replaced by the percent-encoded query. Returns nil for
    /// empty/whitespace input and never returns a non-http(s) URL (javascript:, file:, data:, ftp:, custom
    /// schemes are treated as search text) because `SFSafariViewController` crashes on non-http(s) URLs.
    public static func url(for input: String, searchTemplate: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains(where: { $0.isWhitespace }) {
            let lower = text.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://"), let url = webURL(text) {
                return url
            }
            if looksLikeHost(text), let url = webURL("https://" + text) {
                return url
            }
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        guard let query = text.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return webURL(searchTemplate.replacingOccurrences(of: "%@", with: query))
    }

    /// True when the part before the first "/" or ":" has a dot, no "@" (an email or userinfo is searched, not
    /// opened), no empty labels and a letter-only TLD of 2+.
    private static func looksLikeHost(_ text: String) -> Bool {
        guard let host = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" || $0 == ":" }).first,
              !host.contains("@")
        else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, !labels.contains(where: { $0.isEmpty }), let tld = labels.last else { return false }
        return tld.count >= 2 && tld.allSatisfy { $0.isLetter }
    }

    /// The URL only if it parses with an http(s) scheme and a non-empty host.
    private static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
