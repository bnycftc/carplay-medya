import Foundation

/// A content source the user added. The app ships with none.
///
/// This value is safe to persist (it is `Codable`): it never contains a password.
/// Xtream passwords belong in the Keychain (`kSecAttrAccessibleAfterFirstUnlock`, so CarPlay
/// works while the phone is locked) and are combined via ``XtreamAccount/credentials(password:)``.
public enum MediaSource: Sendable, Hashable, Codable, Identifiable {
    /// A remote M3U/M3U8 channel list.
    case m3uURL(id: String, name: String, url: URL, userAgent: String? = nil)
    /// An Xtream Codes account.
    case xtream(id: String, name: String, account: XtreamAccount)
    /// A playlist or media file imported from Files / the share sheet.
    case localFile(id: String, name: String, bookmark: Data)

    /// Stable id of the source.
    public var id: String {
        switch self {
        case .m3uURL(let id, _, _, _), .xtream(let id, _, _), .localFile(let id, _, _):
            return id
        }
    }

    /// User-visible name.
    public var name: String {
        switch self {
        case .m3uURL(_, let name, _, _), .xtream(_, let name, _), .localFile(_, let name, _):
            return name
        }
    }
}

/// The non-secret part of an Xtream login.
public struct XtreamAccount: Sendable, Hashable, Codable {
    /// Normalized server base URL (`scheme://host[:port][/path]`, no trailing slash).
    public var baseURL: URL
    /// Account username.
    public var username: String

    /// Creates an account descriptor.
    public init(baseURL: URL, username: String) {
        self.baseURL = baseURL
        self.username = username
    }

    /// Combines this account with a password fetched from secure storage.
    public func credentials(password: String) throws -> XtreamCredentials {
        try XtreamCredentials(baseURL: baseURL, username: username, password: password)
    }
}
