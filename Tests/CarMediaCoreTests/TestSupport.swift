import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CarMediaCore

enum Fixture {
    /// URL of a fixture file, via `Bundle.module` (falls back to the source tree if resources are missing).
    static func url(_ name: String) throws -> URL {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        if let url = Bundle.module.url(forResource: parts[0], withExtension: parts.count > 1 ? parts[1] : nil,
                                       subdirectory: "Fixtures") {
            return url
        }
        let fallback = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: fallback.path) else {
            throw XCTSkip("Fixture \(name) not found")
        }
        return fallback
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }
}

/// Stub transport that answers from a routing closure and records requests.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data, [String: String])

    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Routes `player_api.php` requests by their `action` query item to fixture files.
    static func xtream(fixtures: [String: String], status: Int = 200) -> StubTransport {
        StubTransport { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let action = items.first { $0.name == "action" }?.value ?? ""
            guard let file = fixtures[action] else { return (404, Data(), [:]) }
            return (status, try Fixture.data(file), ["Content-Type": "application/json"])
        }
    }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    private func record(_ request: URLRequest) {
        lock.lock()
        recorded.append(request)
        lock.unlock()
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        record(request)
        let (status, body, headers) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (body, response)
    }
}

extension XCTestCase {
    /// Asserts that `body` throws exactly `expected`.
    func assertThrows<T>(
        _ expected: CarMediaError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> T
    ) {
        do {
            _ = try body()
            XCTFail("Expected \(expected) but no error was thrown", file: file, line: line)
        } catch let error as CarMediaError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error \(error)", file: file, line: line)
        }
    }

    /// Async variant of ``assertThrows(_:file:line:_:)``.
    func assertThrowsAsync<T>(
        _ expected: CarMediaError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> T
    ) async {
        do {
            _ = try await body()
            XCTFail("Expected \(expected) but no error was thrown", file: file, line: line)
        } catch let error as CarMediaError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error \(error)", file: file, line: line)
        }
    }
}
