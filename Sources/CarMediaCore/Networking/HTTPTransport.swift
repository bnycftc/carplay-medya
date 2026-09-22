import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal async HTTP abstraction so parsers and clients can be tested with stub transports.
public protocol HTTPTransport: Sendable {
    /// Performs the request and returns the body and HTTP response.
    /// Non-2xx responses are returned, not thrown; callers decide how to treat them.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Builds `URLRequest`s with the headers IPTV servers commonly require.
public enum HTTPRequestBuilder {
    /// Creates a GET request.
    ///
    /// - Parameters:
    ///   - userAgent: overrides the transport's default `User-Agent` (e.g. from `#EXTVLCOPT:http-user-agent`).
    ///   - referrer: sets `Referer` (e.g. from `#EXTVLCOPT:http-referrer`).
    ///   - timeout: per-request timeout; `nil` keeps the transport default.
    public static func get(
        _ url: URL,
        userAgent: String? = nil,
        referrer: String? = nil,
        timeout: TimeInterval? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let timeout { request.timeoutInterval = timeout }
        if let userAgent, !userAgent.isEmpty { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        if let referrer, !referrer.isEmpty { request.setValue(referrer, forHTTPHeaderField: "Referer") }
        return request
    }
}
