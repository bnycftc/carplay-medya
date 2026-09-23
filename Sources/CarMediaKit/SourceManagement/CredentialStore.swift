import Foundation

/// Secure storage for Xtream passwords, keyed by source id.
///
/// The app implements this with the Keychain (`kSecAttrAccessibleAfterFirstUnlock`, so CarPlay can
/// refresh sources while the phone is locked). Implementations must never log the password.
public protocol CredentialStore: Sendable {
    /// The stored password, or `nil` if none.
    func password(forSourceID id: String) throws -> String?
    /// Stores or replaces the password.
    func setPassword(_ password: String, forSourceID id: String) throws
    /// Deletes the password (no error if absent).
    func removePassword(forSourceID id: String) throws
}

/// Thread-safe in-memory ``CredentialStore`` for tests and previews.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var passwords: [String: String]

    /// Creates a store with optional initial contents.
    public init(passwords: [String: String] = [:]) {
        self.passwords = passwords
    }

    public func password(forSourceID id: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return passwords[id]
    }

    public func setPassword(_ password: String, forSourceID id: String) throws {
        lock.lock(); defer { lock.unlock() }
        passwords[id] = password
    }

    public func removePassword(forSourceID id: String) throws {
        lock.lock(); defer { lock.unlock() }
        passwords[id] = nil
    }
}
