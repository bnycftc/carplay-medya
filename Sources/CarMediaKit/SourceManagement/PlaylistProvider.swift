import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CarMediaCore

/// Loads the channel list of a source.
public protocol PlaylistProvider: Sendable {
    /// Loads (downloads, reads, parses) the playlist of `source`.
    func loadPlaylist(for source: MediaSource) async throws -> Playlist
}

/// Loads the programme guide of a source, if it announces one.
public protocol GuideProvider: Sendable {
    /// Returns the guide, or `nil` when the source has no guide address.
    func loadGuide(for source: MediaSource, playlist: Playlist) async throws -> EPGStore?
}

/// Default provider: M3U over HTTP, Xtream `player_api.php`, and imported local files.
///
/// Platform specifics are injected so this stays Foundation-only:
/// - `credentials` reads Xtream passwords (the app uses the Keychain),
/// - `resolveBookmark` turns a stored bookmark into a readable file URL.
public struct DefaultPlaylistProvider: PlaylistProvider, GuideProvider {
    /// Resolves bookmark data stored in ``MediaSource/localFile(id:name:bookmark:)``.
    public typealias BookmarkResolver = @Sendable (Data) throws -> URL
    /// Inflates a gzip file (`.xml.gz` guides). Foundation has no portable inflater, so the app injects one.
    public typealias GzipInflater = @Sendable (Data) throws -> Data

    private let transport: any HTTPTransport
    private let credentials: any CredentialStore
    private let resolveBookmark: BookmarkResolver
    private let inflateGzip: GzipInflater?

    /// Creates a provider.
    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        credentials: any CredentialStore,
        resolveBookmark: @escaping BookmarkResolver,
        inflateGzip: GzipInflater? = nil
    ) {
        self.transport = transport
        self.credentials = credentials
        self.resolveBookmark = resolveBookmark
        self.inflateGzip = inflateGzip
    }

    // MARK: Playlists

    public func loadPlaylist(for source: MediaSource) async throws -> Playlist {
        switch source {
        case .m3uURL(_, _, let url, let userAgent):
            return try await PlaylistLoader(transport: transport).load(from: url, userAgent: userAgent)
        case .xtream(let id, _, let account):
            let client = try xtreamClient(sourceID: id, account: account)
            async let categories = client.liveCategories()
            let streams = try await client.liveStreams()
            // Categories are cosmetic (group names); a failure there should not fail the refresh.
            let names = (try? await categories) ?? []
            return Playlist(channels: client.channels(from: streams, categories: names, format: .hls))
        case .localFile(let id, let name, let bookmark):
            let url: URL
            do {
                url = try resolveBookmark(bookmark)
            } catch {
                throw SourceStoreError.fileUnavailable
            }
            return try Self.loadLocalFile(url, sourceID: id, name: name)
        }
    }

    /// Reads an imported file: a channel list is parsed, a single media file becomes a one-item playlist.
    public static func loadLocalFile(_ url: URL, sourceID: String, name: String) throws -> Playlist {
        switch MediaContainer.infer(from: url) {
        case .mpeg4, .audio, .mpegTS, .unsupported:
            return singleItemPlaylist(url: url, sourceID: sourceID, name: name)
        case .hls, .unknown:
            break
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SourceStoreError.fileUnavailable
        }
        if TextDecoding.isGzip(data) { throw CarMediaError.compressedDataNotSupported }
        switch PlaylistSniffer.classify(data: data) {
        case .channelPlaylist:
            return try M3UParser().parse(data: data, baseURL: url)
        case .hlsMediaPlaylist, .binaryMedia:
            return singleItemPlaylist(url: url, sourceID: sourceID, name: name)
        case .unknown:
            throw CarMediaError.notAChannelList(.unknown)
        }
    }

    static func singleItemPlaylist(url: URL, sourceID: String, name: String) -> Playlist {
        let title = name.isEmpty ? url.deletingPathExtension().lastPathComponent : name
        let container = MediaContainer.infer(from: url)
        let channel = Channel(
            id: StableID.make("local", sourceID),
            title: title,
            streamURL: url,
            kind: .movie,
            isRadio: container == .audio
        )
        return Playlist(channels: [channel])
    }

    // MARK: Guides

    public func loadGuide(for source: MediaSource, playlist: Playlist) async throws -> EPGStore? {
        let guideURL: URL?
        var secrets: [String] = []
        switch source {
        case .xtream(let id, _, let account):
            let client = try xtreamClient(sourceID: id, account: account)
            guideURL = client.endpoints.xmltvURL
            secrets = [client.endpoints.credentials.password]
        case .m3uURL, .localFile:
            guideURL = playlist.epgURLs.first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        }
        guard let guideURL else { return nil }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: HTTPRequestBuilder.get(guideURL))
        } catch let error as CarMediaError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CarMediaError.transport(UserFacingError.redactedDetail(of: error, secrets: secrets))
        }
        guard (200..<300).contains(response.statusCode) else { throw CarMediaError.httpStatus(response.statusCode) }
        var xml = data
        if TextDecoding.isGzip(xml) {
            guard let inflateGzip else { throw CarMediaError.compressedDataNotSupported }
            do {
                xml = try inflateGzip(xml)
            } catch {
                throw CarMediaError.compressedDataNotSupported
            }
        }
        return try XMLTVParser.parse(data: xml).makeStore()
    }

    // MARK: Helpers

    /// Builds an Xtream client with the password from secure storage.
    public func xtreamClient(sourceID: String, account: XtreamAccount) throws -> XtreamClient {
        guard let password = try? credentials.password(forSourceID: sourceID), !password.isEmpty else {
            throw SourceStoreError.missingPassword
        }
        return XtreamClient(credentials: try account.credentials(password: password), transport: transport)
    }
}
