import Foundation

/// A playable item from a user-supplied source (M3U entry or Xtream stream).
///
/// `id` is deterministic (see ``StableID``) so favorites and "recently played" survive re-imports.
/// Note: for Xtream sources `streamURL` embeds the account password in its path; persist `id`,
/// not the URL, and rebuild URLs from Keychain-held credentials.
public struct Channel: Sendable, Hashable, Codable, Identifiable {
    /// Stable identifier.
    public var id: String
    /// Display title.
    public var title: String
    /// URL handed to AVPlayer.
    public var streamURL: URL
    /// Live, movie or series episode.
    public var kind: StreamKind
    /// Group/category name, if any.
    public var groupTitle: String?
    /// `tvg-id`: the XMLTV channel id used to look up the programme guide.
    public var tvgID: String?
    /// `tvg-name`: alternative name used for EPG matching.
    public var tvgName: String?
    /// Channel logo address as written in the source (`tvg-logo` / `stream_icon`).
    /// Kept as text so importing large lists does not pay for URL parsing; see ``logoURL``.
    public var logo: String?
    /// `tvg-chno` channel number.
    public var channelNumber: Int?
    /// `tvg-language`.
    public var language: String?
    /// `tvg-country`.
    public var country: String?
    /// `catchup` mode (e.g. `default`, `append`, `shift`, `flussonic`).
    public var catchup: String?
    /// `catchup-source` template.
    public var catchupSource: String?
    /// Duration from `#EXTINF` (`-1` or `0` for live streams).
    public var duration: Double?
    /// `true` for audio-only (radio) entries (`radio="true"` attribute).
    public var isRadio: Bool
    /// HTTP `User-Agent` the stream requires (`#EXTVLCOPT:http-user-agent` or `|User-Agent=`).
    public var userAgent: String?
    /// HTTP `Referer` the stream requires (`#EXTVLCOPT:http-referrer` or `|Referer=`).
    public var referrer: String?
    /// All `#EXTVLCOPT` options, keys lowercased.
    public var vlcOptions: [String: String]
    /// All `#KODIPROP` properties, keys lowercased.
    public var kodiProperties: [String: String]
    /// All raw `#EXTINF` attributes, keys lowercased.
    public var attributes: [String: String]

    /// Creates a channel. Only `id`, `title` and `streamURL` are required.
    public init(
        id: String,
        title: String,
        streamURL: URL,
        kind: StreamKind = .live,
        groupTitle: String? = nil,
        tvgID: String? = nil,
        tvgName: String? = nil,
        logo: String? = nil,
        channelNumber: Int? = nil,
        language: String? = nil,
        country: String? = nil,
        catchup: String? = nil,
        catchupSource: String? = nil,
        duration: Double? = nil,
        isRadio: Bool = false,
        userAgent: String? = nil,
        referrer: String? = nil,
        vlcOptions: [String: String] = [:],
        kodiProperties: [String: String] = [:],
        attributes: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.streamURL = streamURL
        self.kind = kind
        self.groupTitle = groupTitle
        self.tvgID = tvgID
        self.tvgName = tvgName
        self.logo = logo
        self.channelNumber = channelNumber
        self.language = language
        self.country = country
        self.catchup = catchup
        self.catchupSource = catchupSource
        self.duration = duration
        self.isRadio = isRadio
        self.userAgent = userAgent
        self.referrer = referrer
        self.vlcOptions = vlcOptions
        self.kodiProperties = kodiProperties
        self.attributes = attributes
    }

    /// The channel logo as a URL (spaces and non-ASCII characters percent-encoded), if valid.
    public var logoURL: URL? {
        logo.flatMap { PercentEncoding.lenientURL($0) }
    }

    /// The container inferred from the stream URL.
    public var container: MediaContainer { MediaContainer.infer(from: streamURL) }

    /// HTTP headers to attach when opening the stream (e.g. via `AVURLAssetHTTPHeaderFieldsKey`).
    public var httpHeaders: [String: String] {
        var headers: [String: String] = [:]
        if let userAgent { headers["User-Agent"] = userAgent }
        if let referrer { headers["Referer"] = referrer }
        return headers
    }

    /// The default stable id for an M3U entry: a hash of the stream URL and title.
    public static func stableID(url: URL, title: String) -> String {
        StableID.make(url.absoluteString, title)
    }
}
