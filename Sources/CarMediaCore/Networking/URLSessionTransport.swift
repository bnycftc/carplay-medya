import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Default ``HTTPTransport`` backed by `URLSession`.
///
/// Uses the completion-handler API internally so it behaves the same on Apple platforms and
/// on Windows/Linux (swift-corelibs-foundation). Supports task cancellation.
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    /// How HTTP redirects are handled.
    public enum RedirectPolicy: Sendable, Equatable {
        /// Follow every redirect.
        case follow
        /// Follow redirects, except from `https` to plain `http` (default: avoids silently leaking credentials).
        case followWithoutDowngrade
        /// Follow only redirects that stay on the original host.
        case sameHostOnly
        /// Never follow; the 3xx response is returned to the caller.
        case refuse
    }

    /// Transport settings.
    public struct Configuration: Sendable {
        /// Timeout while waiting for data (seconds).
        public var requestTimeout: TimeInterval
        /// Maximum total time for a request (seconds). Large playlists/EPGs may need more.
        public var resourceTimeout: TimeInterval
        /// Default `User-Agent`, applied when a request does not set its own.
        public var userAgent: String?
        /// Redirect handling.
        public var redirectPolicy: RedirectPolicy

        /// Creates a configuration.
        public init(
            requestTimeout: TimeInterval = 20,
            resourceTimeout: TimeInterval = 120,
            userAgent: String? = "CarMediaCore/1.0",
            redirectPolicy: RedirectPolicy = .followWithoutDowngrade
        ) {
            self.requestTimeout = requestTimeout
            self.resourceTimeout = resourceTimeout
            self.userAgent = userAgent
            self.redirectPolicy = redirectPolicy
        }
    }

    /// The active configuration.
    public let configuration: Configuration
    private let session: URLSession

    /// Creates a transport with its own ephemeral `URLSession` (no cookies/cache persisted).
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfiguration.timeoutIntervalForResource = configuration.resourceTimeout
        sessionConfiguration.httpShouldSetCookies = false
        let delegate = RedirectDelegate(policy: configuration.redirectPolicy)
        self.session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    /// Performs the request. Throws `CancellationError` if the surrounding task is cancelled.
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if request.value(forHTTPHeaderField: "User-Agent") == nil, let userAgent = configuration.userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        let box = TaskBox()
        let session = self.session
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: box.isCancelled ? CancellationError() : error)
                        return
                    }
                    guard let http = response as? HTTPURLResponse else {
                        continuation.resume(throwing: CarMediaError.transport("Response is not HTTP"))
                        return
                    }
                    continuation.resume(returning: (data ?? Data(), http))
                }
                box.start(task)
            }
        } onCancel: {
            box.cancel()
        }
    }
}

/// Holds a data task so it can be cancelled from a `withTaskCancellationHandler` handler.
private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func start(_ task: URLSessionDataTask) {
        lock.lock()
        self.task = task
        let alreadyCancelled = cancelled
        lock.unlock()
        // A task cancelled before it started still has to deliver its completion handler,
        // so cancel first and then resume (resume is a no-op on a cancelled task).
        if alreadyCancelled { task.cancel() }
        task.resume()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}

private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let policy: URLSessionTransport.RedirectPolicy

    init(policy: URLSessionTransport.RedirectPolicy) {
        self.policy = policy
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(Self.decide(policy: policy, from: task.originalRequest?.url, to: request) ? request : nil)
    }

    static func decide(policy: URLSessionTransport.RedirectPolicy, from original: URL?, to request: URLRequest) -> Bool {
        switch policy {
        case .follow:
            return true
        case .refuse:
            return false
        case .sameHostOnly:
            return original?.host?.lowercased() == request.url?.host?.lowercased()
        case .followWithoutDowngrade:
            let wasSecure = original?.scheme?.lowercased() == "https"
            let isSecure = request.url?.scheme?.lowercased() == "https"
            return !(wasSecure && !isSecure)
        }
    }
}
