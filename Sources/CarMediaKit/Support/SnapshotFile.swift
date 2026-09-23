import Foundation

/// Reads and writes a `Codable` value as a JSON file (atomic writes).
///
/// On iOS the file is written with `completeFileProtectionUntilFirstUserAuthentication` so CarPlay can
/// read it while the phone is locked (matching the app's default data protection class).
public struct SnapshotFile<Value: Codable>: Sendable {
    /// Location of the file.
    public let url: URL

    /// Creates a handle; nothing is read or written yet.
    public init(url: URL) {
        self.url = url
    }

    /// Loads the value, or returns `nil` if the file does not exist.
    /// - Throws: decoding errors for a corrupt file (callers usually fall back to defaults).
    public func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    /// Writes the value, creating the parent directory if needed.
    public func save(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: [.atomic])
        #endif
    }

    /// Deletes the file (no error if it does not exist).
    public func delete() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
