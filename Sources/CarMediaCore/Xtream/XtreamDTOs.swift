import Foundation

// Wire formats of the Xtream Codes `player_api.php`. Every field is optional and decoded leniently:
// panels disagree on types ("1" vs 1 vs true), use "" for missing numbers, and omit keys freely.

// MARK: - Account

/// Response of `player_api.php` without an action (used for the "connection test" screen).
public struct XtreamAccountInfo: Codable, Sendable, Hashable {
    /// Account status block.
    @LossyValue public var userInfo: XtreamUserInfo?
    /// Server block.
    @LossyValue public var serverInfo: XtreamServerInfo?

    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
        case serverInfo = "server_info"
    }
}

/// `user_info`. The password echoed by the server is intentionally not decoded.
public struct XtreamUserInfo: Codable, Sendable, Hashable {
    @LossyString public var username: String?
    @LossyString public var message: String?
    /// `1` when the credentials were accepted.
    @LossyBool public var auth: Bool?
    /// e.g. `Active`, `Expired`, `Banned`, `Disabled`.
    @LossyString public var status: String?
    /// Expiry as Unix seconds; `nil` for unlimited accounts.
    @LossyInt public var expDate: Int?
    @LossyBool public var isTrial: Bool?
    @LossyInt public var activeConnections: Int?
    @LossyInt public var createdAt: Int?
    @LossyInt public var maxConnections: Int?
    @LossyValue public var allowedOutputFormats: [String]?

    enum CodingKeys: String, CodingKey {
        case username, message, auth, status
        case expDate = "exp_date"
        case isTrial = "is_trial"
        case activeConnections = "active_cons"
        case createdAt = "created_at"
        case maxConnections = "max_connections"
        case allowedOutputFormats = "allowed_output_formats"
    }

    /// Expiry date, or `nil` when unlimited/unknown.
    public var expirationDate: Date? {
        guard let expDate, expDate > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(expDate))
    }

    /// `true` when `status` is `Active` (case-insensitive).
    public var isActive: Bool { status?.lowercased() == "active" }

    /// `true` if the server offers HLS output (or does not say).
    public var supportsHLS: Bool {
        guard let formats = allowedOutputFormats, !formats.isEmpty else { return true }
        return formats.contains { $0.lowercased() == "m3u8" || $0.lowercased() == "hls" }
    }
}

/// `server_info`.
public struct XtreamServerInfo: Codable, Sendable, Hashable {
    @LossyString public var url: String?
    @LossyInt public var port: Int?
    @LossyInt public var httpsPort: Int?
    @LossyString public var serverProtocol: String?
    @LossyInt public var rtmpPort: Int?
    @LossyString public var timezone: String?
    @LossyInt public var timestampNow: Int?
    @LossyString public var timeNow: String?

    enum CodingKeys: String, CodingKey {
        case url, port, timezone
        case httpsPort = "https_port"
        case serverProtocol = "server_protocol"
        case rtmpPort = "rtmp_port"
        case timestampNow = "timestamp_now"
        case timeNow = "time_now"
    }
}

// MARK: - Catalog

/// A live/VOD/series category.
public struct XtreamCategory: Codable, Sendable, Hashable, Identifiable {
    @LossyString public var categoryID: String?
    @LossyString public var categoryName: String?
    @LossyInt public var parentID: Int?

    enum CodingKeys: String, CodingKey {
        case categoryID = "category_id"
        case categoryName = "category_name"
        case parentID = "parent_id"
    }

    /// Category id (empty string if the server omitted it).
    public var id: String { categoryID ?? "" }
}

/// An entry of `get_live_streams`.
public struct XtreamLiveStream: Codable, Sendable, Hashable {
    @LossyInt public var num: Int?
    @LossyString public var name: String?
    @LossyString public var streamType: String?
    @LossyInt public var streamID: Int?
    @LossyString public var streamIcon: String?
    @LossyString public var epgChannelID: String?
    @LossyString public var added: String?
    @LossyString public var categoryID: String?
    @LossyString public var customSID: String?
    @LossyBool public var tvArchive: Bool?
    @LossyString public var directSource: String?
    @LossyInt public var tvArchiveDuration: Int?

    enum CodingKeys: String, CodingKey {
        case num, name, added
        case streamType = "stream_type"
        case streamID = "stream_id"
        case streamIcon = "stream_icon"
        case epgChannelID = "epg_channel_id"
        case categoryID = "category_id"
        case customSID = "custom_sid"
        case tvArchive = "tv_archive"
        case directSource = "direct_source"
        case tvArchiveDuration = "tv_archive_duration"
    }

    /// `true` for radio streams (`stream_type` = `radio_streams`).
    public var isRadio: Bool { streamType?.lowercased().hasPrefix("radio") ?? false }
}

/// An entry of `get_vod_streams`.
public struct XtreamVODStream: Codable, Sendable, Hashable {
    @LossyInt public var num: Int?
    @LossyString public var name: String?
    @LossyString public var streamType: String?
    @LossyInt public var streamID: Int?
    @LossyString public var streamIcon: String?
    @LossyDouble public var rating: Double?
    @LossyDouble public var rating5Based: Double?
    @LossyString public var added: String?
    @LossyString public var categoryID: String?
    @LossyString public var containerExtension: String?
    @LossyString public var customSID: String?
    @LossyString public var directSource: String?

    enum CodingKeys: String, CodingKey {
        case num, name, rating, added
        case streamType = "stream_type"
        case streamID = "stream_id"
        case streamIcon = "stream_icon"
        case rating5Based = "rating_5based"
        case categoryID = "category_id"
        case containerExtension = "container_extension"
        case customSID = "custom_sid"
        case directSource = "direct_source"
    }
}

/// An entry of `get_series`.
public struct XtreamSeries: Codable, Sendable, Hashable {
    @LossyInt public var num: Int?
    @LossyString public var name: String?
    @LossyInt public var seriesID: Int?
    @LossyString public var cover: String?
    @LossyString public var plot: String?
    @LossyString public var cast: String?
    @LossyString public var director: String?
    @LossyString public var genre: String?
    @LossyString public var releaseDate: String?
    @LossyString public var lastModified: String?
    @LossyDouble public var rating: Double?
    @LossyDouble public var rating5Based: Double?
    @LossyValue public var backdropPath: [String]?
    @LossyString public var youtubeTrailer: String?
    @LossyString public var episodeRunTime: String?
    @LossyString public var categoryID: String?

    enum CodingKeys: String, CodingKey {
        case num, name, cover, plot, cast, director, genre, rating
        case seriesID = "series_id"
        case releaseDate
        case lastModified = "last_modified"
        case rating5Based = "rating_5based"
        case backdropPath = "backdrop_path"
        case youtubeTrailer = "youtube_trailer"
        case episodeRunTime = "episode_run_time"
        case categoryID = "category_id"
    }
}

// MARK: - Series info

/// Response of `get_series_info`.
public struct XtreamSeriesInfo: Codable, Sendable, Hashable {
    /// Season descriptors.
    public var seasons: [XtreamSeason]
    /// Series metadata.
    public var info: XtreamSeries?
    /// Episodes keyed by season number (as text, e.g. `"1"`).
    public var episodes: [String: [XtreamEpisode]]

    enum CodingKeys: String, CodingKey {
        case seasons, info, episodes
    }

    /// Creates a value.
    public init(seasons: [XtreamSeason] = [], info: XtreamSeries? = nil, episodes: [String: [XtreamEpisode]] = [:]) {
        self.seasons = seasons
        self.info = info
        self.episodes = episodes
    }

    /// Decodes leniently. `episodes` may be an object keyed by season or an array of arrays.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seasons = (try? container.decode(LossyList<XtreamSeason>.self, forKey: .seasons))?.elements ?? []
        info = try? container.decode(XtreamSeries.self, forKey: .info)
        if let keyed = try? container.decode([String: LossyList<XtreamEpisode>].self, forKey: .episodes) {
            episodes = keyed.mapValues(\.elements)
        } else if let nested = try? container.decode([LossyList<XtreamEpisode>].self, forKey: .episodes) {
            var result: [String: [XtreamEpisode]] = [:]
            for (index, list) in nested.enumerated() {
                let season = list.elements.first?.season.map(String.init) ?? String(index + 1)
                result[season, default: []].append(contentsOf: list.elements)
            }
            episodes = result
        } else {
            episodes = [:]
        }
    }

    /// Episodes sorted by season number, then episode number.
    public var sortedEpisodes: [XtreamEpisode] {
        episodes.keys
            .sorted { (Int($0) ?? .max, $0) < (Int($1) ?? .max, $1) }
            .flatMap { key in (episodes[key] ?? []).sorted { ($0.episodeNum ?? .max) < ($1.episodeNum ?? .max) } }
    }
}

/// A season descriptor in `get_series_info`.
public struct XtreamSeason: Codable, Sendable, Hashable {
    @LossyInt public var seasonNumber: Int?
    @LossyString public var name: String?
    @LossyInt public var episodeCount: Int?
    @LossyString public var cover: String?
    @LossyString public var airDate: String?

    enum CodingKeys: String, CodingKey {
        case name, cover
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
        case airDate = "air_date"
    }
}

/// An episode in `get_series_info`.
public struct XtreamEpisode: Codable, Sendable, Hashable, Identifiable {
    /// Episode stream id (used in `/series/…/{id}.{ext}`).
    @LossyString public var episodeID: String?
    @LossyInt public var episodeNum: Int?
    @LossyString public var title: String?
    @LossyString public var containerExtension: String?
    @LossyInt public var season: Int?
    @LossyString public var added: String?
    @LossyValue public var info: XtreamEpisodeDetails?

    enum CodingKeys: String, CodingKey {
        case title, season, added, info
        case episodeID = "id"
        case episodeNum = "episode_num"
        case containerExtension = "container_extension"
    }

    /// Episode id (empty string if missing).
    public var id: String { episodeID ?? "" }
}

/// `info` block of an episode.
public struct XtreamEpisodeDetails: Codable, Sendable, Hashable {
    @LossyString public var plot: String?
    @LossyString public var movieImage: String?
    @LossyInt public var durationSecs: Int?
    @LossyString public var duration: String?
    @LossyDouble public var rating: Double?
    @LossyString public var releaseDate: String?

    enum CodingKeys: String, CodingKey {
        case plot, duration, rating
        case movieImage = "movie_image"
        case durationSecs = "duration_secs"
        case releaseDate = "releasedate"
    }
}

// MARK: - VOD info

/// Response of `get_vod_info`. Panels return `"info": []` when metadata is missing.
public struct XtreamVODInfo: Codable, Sendable, Hashable {
    @LossyValue public var info: XtreamVODDetails?
    @LossyValue public var movieData: XtreamMovieData?

    enum CodingKeys: String, CodingKey {
        case info
        case movieData = "movie_data"
    }
}

/// `info` block of `get_vod_info`.
public struct XtreamVODDetails: Codable, Sendable, Hashable {
    @LossyString public var name: String?
    @LossyString public var plot: String?
    @LossyString public var genre: String?
    @LossyString public var director: String?
    @LossyString public var cast: String?
    @LossyString public var releaseDate: String?
    @LossyInt public var durationSecs: Int?
    @LossyString public var duration: String?
    @LossyDouble public var rating: Double?
    @LossyString public var movieImage: String?
    @LossyValue public var backdropPath: [String]?

    enum CodingKeys: String, CodingKey {
        case name, plot, genre, director, cast, duration, rating
        case releaseDate = "releasedate"
        case durationSecs = "duration_secs"
        case movieImage = "movie_image"
        case backdropPath = "backdrop_path"
    }
}

/// `movie_data` block of `get_vod_info`.
public struct XtreamMovieData: Codable, Sendable, Hashable {
    @LossyInt public var streamID: Int?
    @LossyString public var name: String?
    @LossyString public var added: String?
    @LossyString public var categoryID: String?
    @LossyString public var containerExtension: String?

    enum CodingKeys: String, CodingKey {
        case name, added
        case streamID = "stream_id"
        case categoryID = "category_id"
        case containerExtension = "container_extension"
    }
}

// MARK: - EPG

/// Response wrapper of `get_short_epg` / `get_simple_data_table`.
public struct XtreamEPGResponse: Codable, Sendable, Hashable {
    /// Listings; empty when the server has no guide for the stream.
    public var listings: [XtreamEPGListing]

    enum CodingKeys: String, CodingKey {
        case listings = "epg_listings"
    }

    /// Creates a value.
    public init(listings: [XtreamEPGListing]) { self.listings = listings }

    /// Decodes leniently; a missing or malformed `epg_listings` yields an empty list.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        listings = (try? container.decode(LossyList<XtreamEPGListing>.self, forKey: .listings))?.elements ?? []
    }
}

/// One EPG row. `title` and `description` are base64 on the wire; use the decoded accessors.
public struct XtreamEPGListing: Codable, Sendable, Hashable {
    @LossyString public var id: String?
    @LossyString public var epgID: String?
    /// Base64-encoded title as sent by the server.
    @LossyString public var title: String?
    @LossyString public var lang: String?
    /// Server-local `yyyy-MM-dd HH:mm:ss`; prefer ``startTimestamp``.
    @LossyString public var start: String?
    @LossyString public var end: String?
    /// Base64-encoded description as sent by the server.
    @LossyString public var description: String?
    @LossyString public var channelID: String?
    @LossyInt public var startTimestamp: Int?
    @LossyInt public var stopTimestamp: Int?
    @LossyBool public var nowPlaying: Bool?
    @LossyBool public var hasArchive: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, lang, start, end, description
        case epgID = "epg_id"
        case channelID = "channel_id"
        case startTimestamp = "start_timestamp"
        case stopTimestamp = "stop_timestamp"
        case nowPlaying = "now_playing"
        case hasArchive = "has_archive"
    }

    /// Title decoded from base64 (falls back to the raw text if it is not valid base64).
    public var decodedTitle: String { Base64Text.decode(title) ?? "" }

    /// Description decoded from base64 (falls back to the raw text if it is not valid base64).
    public var decodedDescription: String? {
        guard let text = Base64Text.decode(description), !text.isEmpty else { return nil }
        return text
    }

    /// Start time from `start_timestamp`, falling back to `start` interpreted as UTC.
    public var startDate: Date? {
        if let startTimestamp { return Date(timeIntervalSince1970: TimeInterval(startTimestamp)) }
        return start.flatMap(DateParsing.xtreamDateTime)
    }

    /// Stop time from `stop_timestamp`, falling back to `end` interpreted as UTC.
    public var stopDate: Date? {
        if let stopTimestamp { return Date(timeIntervalSince1970: TimeInterval(stopTimestamp)) }
        return end.flatMap(DateParsing.xtreamDateTime)
    }

    /// Converts to a ``Programme``; `nil` if the times are missing.
    public func programme(channelID fallbackChannelID: String? = nil) -> Programme? {
        guard let startDate, let stopDate else { return nil }
        return Programme(
            channelID: channelID ?? fallbackChannelID ?? epgID ?? "",
            start: startDate,
            stop: stopDate,
            title: decodedTitle,
            description: decodedDescription
        )
    }
}

/// Lenient base64 text decoding (missing padding, URL-safe alphabet, whitespace).
enum Base64Text {
    static func decode(_ text: String?) -> String? {
        guard let text else { return nil }
        var cleaned = text.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = cleaned.count % 4
        if remainder > 0 { cleaned += String(repeating: "=", count: 4 - remainder) }
        if let data = Data(base64Encoded: cleaned), let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        return text
    }
}
