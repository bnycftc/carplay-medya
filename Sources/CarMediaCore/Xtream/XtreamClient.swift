import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Async client for the Xtream Codes `player_api.php`.
///
/// Errors never contain the password: transport and decoding messages are passed through ``Redaction``.
public struct XtreamClient: Sendable {
    /// URL builder for this account.
    public let endpoints: XtreamEndpoints
    private let transport: any HTTPTransport

    /// Creates a client.
    public init(credentials: XtreamCredentials, transport: any HTTPTransport = URLSessionTransport()) {
        self.endpoints = XtreamEndpoints(credentials: credentials)
        self.transport = transport
    }

    // MARK: Account

    /// Fetches account and server info.
    /// - Throws: ``CarMediaError/authenticationFailed`` if the server rejects the credentials.
    public func accountInfo() async throws -> XtreamAccountInfo {
        let data = try await fetch(endpoints.accountInfo)
        if Self.isEmptyJSON(data) { throw CarMediaError.authenticationFailed }
        let info: XtreamAccountInfo = try decode(data)
        if info.userInfo?.auth == false || info.userInfo == nil {
            throw CarMediaError.authenticationFailed
        }
        return info
    }

    // MARK: Categories

    /// `get_live_categories`.
    public func liveCategories() async throws -> [XtreamCategory] {
        try await list(endpoints.liveCategories)
    }

    /// `get_vod_categories`.
    public func vodCategories() async throws -> [XtreamCategory] {
        try await list(endpoints.vodCategories)
    }

    /// `get_series_categories`.
    public func seriesCategories() async throws -> [XtreamCategory] {
        try await list(endpoints.seriesCategories)
    }

    // MARK: Streams

    /// `get_live_streams`, optionally for one category.
    public func liveStreams(categoryID: String? = nil) async throws -> [XtreamLiveStream] {
        try await list(endpoints.liveStreams(categoryID: categoryID))
    }

    /// `get_vod_streams`, optionally for one category.
    public func vodStreams(categoryID: String? = nil) async throws -> [XtreamVODStream] {
        try await list(endpoints.vodStreams(categoryID: categoryID))
    }

    /// `get_series`, optionally for one category.
    public func series(categoryID: String? = nil) async throws -> [XtreamSeries] {
        try await list(endpoints.series(categoryID: categoryID))
    }

    /// `get_series_info`.
    public func seriesInfo(seriesID: Int) async throws -> XtreamSeriesInfo {
        try decode(try await fetch(endpoints.seriesInfo(seriesID: seriesID)))
    }

    /// `get_vod_info`.
    public func vodInfo(vodID: Int) async throws -> XtreamVODInfo {
        try decode(try await fetch(endpoints.vodInfo(vodID: vodID)))
    }

    // MARK: EPG

    /// `get_short_epg` (a few upcoming programmes, titles already base64-encoded on the wire).
    public func shortEPG(streamID: Int, limit: Int? = nil) async throws -> [XtreamEPGListing] {
        let data = try await fetch(endpoints.shortEPG(streamID: streamID, limit: limit))
        if Self.isEmptyJSON(data) { return [] }
        let response: XtreamEPGResponse = try decode(data)
        return response.listings
    }

    /// `get_simple_data_table` (full guide for one stream).
    public func simpleDataTable(streamID: Int) async throws -> [XtreamEPGListing] {
        let data = try await fetch(endpoints.simpleDataTable(streamID: streamID))
        if Self.isEmptyJSON(data) { return [] }
        let response: XtreamEPGResponse = try decode(data)
        return response.listings
    }

    // MARK: Channel mapping

    /// Converts live streams to ``Channel``s, resolving category names.
    ///
    /// Channel ids hash host, username and stream id (not the password), so favorites survive a password change.
    public func channels(
        from streams: [XtreamLiveStream],
        categories: [XtreamCategory] = [],
        format: XtreamLiveFormat = .hls
    ) -> [Channel] {
        let names = Dictionary(
            categories.compactMap { c in c.categoryID.map { ($0, c.categoryName ?? "") } },
            uniquingKeysWith: { first, _ in first }
        )
        let host = endpoints.credentials.baseURL.absoluteString
        let user = endpoints.credentials.username
        return streams.compactMap { stream in
            guard let streamID = stream.streamID else { return nil }
            let title = stream.name?.trimmingCharacters(in: .whitespaces) ?? ""
            let group = stream.categoryID.flatMap { names[$0] }.flatMap { $0.isEmpty ? nil : $0 }
            let epgID = stream.epgChannelID.flatMap { $0.isEmpty ? nil : $0 }
            return Channel(
                id: StableID.make("xtream", host, user, "live", String(streamID)),
                title: title.isEmpty ? "#\(streamID)" : title,
                streamURL: endpoints.liveStreamURL(streamID: streamID, format: format),
                kind: .live,
                groupTitle: group,
                tvgID: epgID,
                logo: stream.streamIcon.flatMap { $0.isEmpty ? nil : $0 },
                channelNumber: stream.num,
                catchup: (stream.tvArchive ?? false) ? "xc" : nil,
                isRadio: stream.isRadio
            )
        }
    }

    // MARK: Plumbing

    private func list<T: Decodable>(_ url: URL) async throws -> [T] {
        let data = try await fetch(url)
        if Self.isEmptyJSON(data) { return [] }
        if Self.isAuthFailure(data) { throw CarMediaError.authenticationFailed }
        let list: LossyList<T> = try decode(data)
        return list.elements
    }

    private func fetch(_ url: URL) async throws -> Data {
        let request = HTTPRequestBuilder.get(url)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as CarMediaError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CarMediaError.transport(redact(String(describing: error)))
        }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw CarMediaError.authenticationFailed
        default: throw CarMediaError.httpStatus(response.statusCode)
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if Self.isAuthFailure(data) { throw CarMediaError.authenticationFailed }
            throw CarMediaError.decoding(redact(String(describing: error)))
        }
    }

    private func redact(_ text: String) -> String {
        Redaction.redact(text, secrets: [endpoints.credentials.password])
    }

    /// Empty body, `null`, `[]` or `{}`.
    static func isEmptyJSON(_ data: Data) -> Bool {
        let text = String(decoding: data.prefix(16), as: UTF8.self).filter { !$0.isWhitespace }
        return data.count < 16 && ["", "null", "[]", "{}"].contains(text)
    }

    /// `{"user_info":{"auth":0}}`, which panels return instead of lists for bad credentials.
    static func isAuthFailure(_ data: Data) -> Bool {
        // Only objects can be auth failures; avoid re-parsing large list payloads.
        guard data.first(where: { !($0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D) }) == UInt8(ascii: "{"),
              let info = try? JSONDecoder().decode(XtreamAccountInfo.self, from: data) else { return false }
        return info.userInfo?.auth == false
    }
}
