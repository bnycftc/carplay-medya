import Foundation

/// Login for an Xtream Codes compatible server.
///
/// The password is never printed: `description`, `debugDescription` and `dump()` redact it.
/// This type is deliberately not `Codable`; persist ``XtreamAccount`` and keep the password in the Keychain.
public struct XtreamCredentials: Sendable, Hashable {
    /// Normalized base URL: `scheme://host[:port][/path]`, lowercase scheme/host, no trailing slash,
    /// no query, no `player_api.php`/`get.php` suffix.
    public let baseURL: URL
    /// Account username.
    public let username: String
    /// Account password. Never log this.
    public let password: String

    /// Creates credentials from user-typed server text such as `example.com:8080`,
    /// `http://example.com:8080/`, or a pasted `http://example.com/get.php?username=…`.
    ///
    /// - Throws: ``CarMediaError/invalidURL(_:)`` if no http(s) host can be extracted,
    ///   or if username/password are empty.
    public init(baseURL: String, username: String, password: String) throws {
        guard let normalized = XtreamCredentials.normalizeBaseURL(baseURL) else {
            throw CarMediaError.invalidURL("server address")
        }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { throw CarMediaError.invalidURL("username") }
        guard !password.isEmpty else { throw CarMediaError.invalidURL("password") }
        self.baseURL = normalized
        self.username = user
        self.password = password
    }

    /// Creates credentials from a URL (normalized the same way as the string initializer).
    public init(baseURL: URL, username: String, password: String) throws {
        try self.init(baseURL: baseURL.absoluteString, username: username, password: password)
    }

    /// The non-secret part, safe to persist.
    public var account: XtreamAccount {
        XtreamAccount(baseURL: baseURL, username: username)
    }

    /// Normalizes a server address; returns `nil` if it has no http(s) host.
    public static func normalizeBaseURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }
        components.scheme = scheme
        components.host = host.lowercased()
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        var path = components.path
        for suffix in ["/player_api.php", "/panel_api.php", "/get.php", "/xmltv.php"]
        where path.lowercased().hasSuffix(suffix) {
            path = String(path.dropLast(suffix.count))
        }
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path
        return components.url
    }
}

extension XtreamCredentials: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Redacted description.
    public var description: String {
        "XtreamCredentials(baseURL: \(baseURL.absoluteString), username: \(username), password: \(Redaction.placeholder))"
    }

    /// Redacted description.
    public var debugDescription: String { description }

    /// Redacted mirror so `dump()` and debuggers do not reveal the password.
    public var customMirror: Mirror {
        Mirror(self, children: [
            "baseURL": baseURL.absoluteString,
            "username": username,
            "password": Redaction.placeholder,
        ], displayStyle: .struct)
    }
}
