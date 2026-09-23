import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CarMediaCore
@testable import CarMediaKit

/// Stub transport answering from a routing closure. All hosts are `example.com` fixtures.
final class KitStubTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, String)

    private let lock = NSLock()
    private var recorded: [URL] = []
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var requestedURLs: [URL] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    private func record(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        recorded.append(url)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        record(request.url!)
        let (status, body) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
        return (Data(body.utf8), response)
    }
}

/// Provider returning canned playlists or errors per source id.
final class StubPlaylistProvider: PlaylistProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [String: Result<Playlist, Error>]

    init(_ results: [String: Result<Playlist, Error>] = [:]) {
        self.results = results
    }

    func set(_ result: Result<Playlist, Error>, for id: String) {
        lock.lock(); defer { lock.unlock() }
        results[id] = result
    }

    private func result(for id: String) -> Result<Playlist, Error>? {
        lock.lock(); defer { lock.unlock() }
        return results[id]
    }

    func loadPlaylist(for source: MediaSource) async throws -> Playlist {
        guard let result = result(for: source.id) else { throw SourceStoreError.unknownSource }
        return try result.get()
    }
}

enum Sample {
    static func channel(
        _ title: String,
        group: String? = nil,
        url: String? = nil,
        kind: StreamKind = .live,
        isRadio: Bool = false,
        tvgID: String? = nil
    ) -> Channel {
        let streamURL = URL(string: url ?? "http://stream.example.com/\(title.filter { $0.isLetter || $0.isNumber }).m3u8")!
        return Channel(
            id: Channel.stableID(url: streamURL, title: title),
            title: title,
            streamURL: streamURL,
            kind: kind,
            groupTitle: group,
            tvgID: tvgID,
            isRadio: isRadio
        )
    }

    static let listURL = URL(string: "http://lists.example.com/list.m3u")!

    static func m3uSource(id: String = "m3u-1", name: String = "Liste", url: URL = listURL) -> MediaSource {
        .m3uURL(id: id, name: name, url: url)
    }

    static func xtreamSource(id: String = "xt-1", name: String = "Hesap") -> MediaSource {
        .xtream(id: id, name: name, account: XtreamAccount(baseURL: URL(string: "http://panel.example.com:8080")!, username: "demo"))
    }

    static let m3uText = """
    #EXTM3U url-tvg="http://guide.example.com/epg.xml"
    #EXTINF:-1 tvg-id="haber.example" group-title="Haber",Haber Bir
    http://stream.example.com/haber1.m3u8
    #EXTINF:-1 group-title="Müzik" radio="true",Radyo Deneme
    http://stream.example.com/radyo.mp3
    """
}
