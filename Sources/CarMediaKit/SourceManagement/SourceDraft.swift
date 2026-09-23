import Foundation
import CarMediaCore

/// Validates "add source" form input and builds ``MediaSource`` values.
public enum SourceDraft {
    /// A new random source id.
    public static func makeID() -> String {
        UUID().uuidString.lowercased()
    }

    /// Builds an M3U source from user-typed text.
    ///
    /// A missing scheme defaults to `http://`. Only http(s) is accepted.
    /// An empty `name` falls back to the host.
    /// - Throws: ``UserFacingError/invalidAddress``.
    public static func m3uSource(id: String = makeID(), name: String, urlText: String, userAgent: String? = nil) throws -> MediaSource {
        var text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw UserFacingError.invalidAddress }
        if !text.contains("://") { text = "http://" + text }
        guard let url = PercentEncoding.lenientURL(text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            throw UserFacingError.invalidAddress
        }
        let agent = userAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .m3uURL(
            id: id,
            name: displayName(name, fallback: host),
            url: url,
            userAgent: (agent?.isEmpty ?? true) ? nil : agent
        )
    }

    /// Validates Xtream login fields.
    /// - Throws: ``UserFacingError/invalidAddress`` for an unusable server, empty username or empty password.
    public static func xtreamCredentials(server: String, username: String, password: String) throws -> XtreamCredentials {
        do {
            return try XtreamCredentials(baseURL: server, username: username, password: password)
        } catch {
            throw UserFacingError.invalidAddress
        }
    }

    /// Builds an Xtream source (the password is **not** part of it; store it with a ``CredentialStore``).
    public static func xtreamSource(id: String = makeID(), name: String, credentials: XtreamCredentials) -> MediaSource {
        .xtream(id: id, name: displayName(name, fallback: credentials.baseURL.host ?? credentials.username),
                account: credentials.account)
    }

    /// Builds a local-file source named after the file.
    public static func localFileSource(id: String = makeID(), fileName: String, bookmark: Data) -> MediaSource {
        let base = (fileName as NSString).deletingPathExtension
        return .localFile(id: id, name: displayName(base, fallback: fileName), bookmark: bookmark)
    }

    static func displayName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

/// A presentable summary of an Xtream "connection test" (`player_api.php` without action).
public struct XtreamAccountSummary: Sendable, Equatable {
    /// Account status as reported by the panel.
    public enum Status: Sendable, Equatable {
        case active
        case expired
        case banned
        case disabled
        /// Any other status text (shown verbatim).
        case other(String)
        /// The panel did not report a status.
        case unknown
    }

    /// Account status.
    public var status: Status
    /// Expiry date; `nil` for unlimited/unknown.
    public var expiresAt: Date?
    /// Trial account.
    public var isTrial: Bool
    /// Currently open connections.
    public var activeConnections: Int?
    /// Allowed parallel connections.
    public var maxConnections: Int?
    /// Whether the panel offers HLS (`m3u8`) output, which AVPlayer/CarPlay needs.
    public var supportsHLS: Bool

    /// Creates a summary from the server response.
    public init(info: XtreamAccountInfo) {
        let user = info.userInfo
        switch user?.status?.lowercased() {
        case "active"?: status = .active
        case "expired"?: status = .expired
        case "banned"?: status = .banned
        case "disabled"?: status = .disabled
        case let text? where !text.isEmpty: status = .other(user?.status ?? text)
        default: status = .unknown
        }
        expiresAt = user?.expirationDate
        isTrial = user?.isTrial ?? false
        activeConnections = user?.activeConnections
        maxConnections = user?.maxConnections
        supportsHLS = user?.supportsHLS ?? true
    }

    /// `true` if the account has an expiry date that is not after `date`, or the panel says it expired.
    public func isExpired(at date: Date) -> Bool {
        if status == .expired { return true }
        guard let expiresAt else { return false }
        return expiresAt <= date
    }

    /// Whole days left until expiry (0 on the last day); `nil` when unlimited.
    public func daysRemaining(at date: Date) -> Int? {
        guard let expiresAt else { return nil }
        return max(0, Int(expiresAt.timeIntervalSince(date) / 86_400))
    }

    /// Whether every connection slot is in use (a new stream would likely be refused).
    public var isAtConnectionLimit: Bool {
        guard let activeConnections, let maxConnections, maxConnections > 0 else { return false }
        return activeConnections >= maxConnections
    }
}
