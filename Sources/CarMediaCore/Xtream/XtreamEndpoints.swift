import Foundation

/// `player_api.php` actions.
public enum XtreamAction: String, Sendable, CaseIterable {
    /// `get_live_categories`.
    case getLiveCategories = "get_live_categories"
    /// `get_vod_categories`.
    case getVODCategories = "get_vod_categories"
    /// `get_series_categories`.
    case getSeriesCategories = "get_series_categories"
    /// `get_live_streams`.
    case getLiveStreams = "get_live_streams"
    /// `get_vod_streams`.
    case getVODStreams = "get_vod_streams"
    /// `get_series`.
    case getSeries = "get_series"
    /// `get_series_info`.
    case getSeriesInfo = "get_series_info"
    /// `get_vod_info`.
    case getVODInfo = "get_vod_info"
    /// `get_short_epg`.
    case getShortEPG = "get_short_epg"
    /// `get_simple_data_table`.
    case getSimpleDataTable = "get_simple_data_table"
}

/// Output format for live streams. HLS is preferred: AVPlayer (and therefore CarPlay/AirPlay video)
/// cannot play raw progressive MPEG-TS.
public enum XtreamLiveFormat: String, Sendable, CaseIterable {
    /// `.m3u8` (HLS).
    case hls = "m3u8"
    /// `.ts` (MPEG transport stream).
    case mpegTS = "ts"
}

/// Builds every URL used with an Xtream Codes server.
///
/// URLs contain the password (that is how the Xtream protocol works). Never log them;
/// use ``Redaction`` if a URL must appear in diagnostics.
public struct XtreamEndpoints: Sendable, Hashable {
    /// The account the URLs are built for.
    public let credentials: XtreamCredentials

    /// Creates an endpoint builder.
    public init(credentials: XtreamCredentials) {
        self.credentials = credentials
    }

    // MARK: player_api.php

    /// `player_api.php?username=…&password=…[&action=…][&params…]`.
    /// Extra parameters are appended sorted by key so URLs are deterministic.
    public func playerAPI(action: XtreamAction? = nil, params: [String: String] = [:]) -> URL {
        var query: [(String, String)] = [("username", credentials.username), ("password", credentials.password)]
        if let action { query.append(("action", action.rawValue)) }
        for key in params.keys.sorted() {
            if let value = params[key] { query.append((key, value)) }
        }
        return makeURL(path: "/player_api.php", query: query)
    }

    /// Account and server info (the "connection test"): `player_api.php` without an action.
    public var accountInfo: URL { playerAPI() }

    /// `get_live_categories`.
    public var liveCategories: URL { playerAPI(action: .getLiveCategories) }
    /// `get_vod_categories`.
    public var vodCategories: URL { playerAPI(action: .getVODCategories) }
    /// `get_series_categories`.
    public var seriesCategories: URL { playerAPI(action: .getSeriesCategories) }

    /// `get_live_streams`, optionally filtered by category.
    public func liveStreams(categoryID: String? = nil) -> URL {
        playerAPI(action: .getLiveStreams, params: categoryParams(categoryID))
    }

    /// `get_vod_streams`, optionally filtered by category.
    public func vodStreams(categoryID: String? = nil) -> URL {
        playerAPI(action: .getVODStreams, params: categoryParams(categoryID))
    }

    /// `get_series`, optionally filtered by category.
    public func series(categoryID: String? = nil) -> URL {
        playerAPI(action: .getSeries, params: categoryParams(categoryID))
    }

    /// `get_series_info&series_id=…`.
    public func seriesInfo(seriesID: Int) -> URL {
        playerAPI(action: .getSeriesInfo, params: ["series_id": String(seriesID)])
    }

    /// `get_vod_info&vod_id=…`.
    public func vodInfo(vodID: Int) -> URL {
        playerAPI(action: .getVODInfo, params: ["vod_id": String(vodID)])
    }

    /// `get_short_epg&stream_id=…[&limit=…]`.
    public func shortEPG(streamID: Int, limit: Int? = nil) -> URL {
        var params = ["stream_id": String(streamID)]
        if let limit { params["limit"] = String(limit) }
        return playerAPI(action: .getShortEPG, params: params)
    }

    /// `get_simple_data_table&stream_id=…` (full EPG for one channel).
    public func simpleDataTable(streamID: Int) -> URL {
        playerAPI(action: .getSimpleDataTable, params: ["stream_id": String(streamID)])
    }

    // MARK: Other endpoints

    /// Full XMLTV guide: `xmltv.php?username=…&password=…`.
    public var xmltvURL: URL {
        makeURL(path: "/xmltv.php", query: [("username", credentials.username), ("password", credentials.password)])
    }

    /// M3U export of the account: `get.php?username=…&password=…&type=m3u_plus&output=…`.
    public func m3uURL(output: XtreamLiveFormat = .hls) -> URL {
        makeURL(path: "/get.php", query: [
            ("username", credentials.username), ("password", credentials.password),
            ("type", "m3u_plus"), ("output", output.rawValue),
        ])
    }

    // MARK: Stream URLs

    /// Live stream: `/live/{user}/{pass}/{id}.m3u8` (or `.ts`).
    public func liveStreamURL(streamID: Int, format: XtreamLiveFormat = .hls) -> URL {
        streamURL(kind: "live", id: String(streamID), ext: format.rawValue)
    }

    /// Movie: `/movie/{user}/{pass}/{id}.{ext}`; `containerExtension` comes from the VOD listing (`mp4`, `mkv`…).
    public func movieURL(streamID: Int, containerExtension: String?) -> URL {
        streamURL(kind: "movie", id: String(streamID), ext: Self.sanitizedExtension(containerExtension))
    }

    /// Series episode: `/series/{user}/{pass}/{episodeID}.{ext}`.
    public func seriesEpisodeURL(episodeID: String, containerExtension: String?) -> URL {
        streamURL(kind: "series", id: PercentEncoding.encodeComponent(episodeID),
                  ext: Self.sanitizedExtension(containerExtension))
    }

    // MARK: Helpers

    private func categoryParams(_ categoryID: String?) -> [String: String] {
        guard let categoryID, !categoryID.isEmpty else { return [:] }
        return ["category_id": categoryID]
    }

    private func streamURL(kind: String, id: String, ext: String) -> URL {
        let path = "/\(kind)/\(PercentEncoding.encodeComponent(credentials.username))/"
            + "\(PercentEncoding.encodeComponent(credentials.password))/\(id).\(ext)"
        return makeURL(path: path, query: [])
    }

    private func makeURL(path: String, query: [(String, String)]) -> URL {
        var text = credentials.baseURL.absoluteString + path
        if !query.isEmpty {
            text += "?" + query
                .map { PercentEncoding.encodeComponent($0.0) + "=" + PercentEncoding.encodeComponent($0.1) }
                .joined(separator: "&")
        }
        guard let url = URL(string: text) else {
            // Unreachable: every dynamic part is percent-encoded to unreserved ASCII.
            preconditionFailure("XtreamEndpoints produced an invalid URL")
        }
        return url
    }

    static func sanitizedExtension(_ raw: String?) -> String {
        let cleaned = (raw ?? "").lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return cleaned.isEmpty ? "mp4" : cleaned
    }
}
