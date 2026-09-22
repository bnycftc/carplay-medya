import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Downloads and parses a remote (or local file) channel list.
public struct PlaylistLoader: Sendable {
    private let transport: any HTTPTransport
    private let parser = M3UParser()

    /// Creates a loader using the given transport.
    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// Loads the playlist at `url`.
    ///
    /// - Parameters:
    ///   - userAgent: sent as `User-Agent` (some providers require a specific one).
    ///   - referrer: sent as `Referer`.
    /// - Throws: ``CarMediaError/notAChannelList(_:)`` when the address is a media stream (HLS, TS, MP4)
    ///   or not a playlist at all, ``CarMediaError/httpStatus(_:)``, ``CarMediaError/emptyPlaylist``, …
    public func load(from url: URL, userAgent: String? = nil, referrer: String? = nil) async throws -> Playlist {
        let data: Data
        var contentType: String?
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            let request = HTTPRequestBuilder.get(url, userAgent: userAgent, referrer: referrer)
            let (body, response) = try await transport.data(for: request)
            guard (200..<300).contains(response.statusCode) else {
                throw CarMediaError.httpStatus(response.statusCode)
            }
            data = body
            contentType = response.value(forHTTPHeaderField: "Content-Type")
        }
        if TextDecoding.isGzip(data) { throw CarMediaError.compressedDataNotSupported }
        switch PlaylistSniffer.classify(data: data, contentTypeHeader: contentType) {
        case .channelPlaylist:
            return try parser.parse(data: data, baseURL: url)
        case .hlsMediaPlaylist:
            throw CarMediaError.notAChannelList(.hlsMediaPlaylist)
        case .binaryMedia:
            throw CarMediaError.notAChannelList(.binaryMedia)
        case .unknown:
            throw CarMediaError.notAChannelList(.unknown)
        }
    }
}
