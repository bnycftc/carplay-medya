import Foundation

/// A raw entry as written in an M3U file, before it is turned into a ``Channel``.
public struct M3UEntry: Sendable, Hashable {
    /// `#EXTINF` duration (`-1` for live).
    public var duration: Double?
    /// Text after the first unquoted comma of `#EXTINF`, trimmed; `nil` if absent or empty.
    public var title: String?
    /// `#EXTINF` attributes, keys lowercased.
    public var attributes: [String: String]
    /// The URL line as written (without any `|Header=…` suffix).
    public var urlString: String
    /// `#EXTGRP:` value preceding the URL.
    public var extGroup: String?
    /// `#EXTVLCOPT:key=value` options, keys lowercased.
    public var vlcOptions: [String: String]
    /// `#KODIPROP:key=value` properties, keys lowercased.
    public var kodiProperties: [String: String]
    /// Kodi-style `url|User-Agent=…&Referer=…` headers, keys lowercased.
    public var pipeHeaders: [String: String]
    /// 1-based line number of the URL line.
    public var lineNumber: Int

    /// Creates an entry.
    public init(
        duration: Double? = nil,
        title: String? = nil,
        attributes: [String: String] = [:],
        urlString: String,
        extGroup: String? = nil,
        vlcOptions: [String: String] = [:],
        kodiProperties: [String: String] = [:],
        pipeHeaders: [String: String] = [:],
        lineNumber: Int = 0
    ) {
        self.duration = duration
        self.title = title
        self.attributes = attributes
        self.urlString = urlString
        self.extGroup = extGroup
        self.vlcOptions = vlcOptions
        self.kodiProperties = kodiProperties
        self.pipeHeaders = pipeHeaders
        self.lineNumber = lineNumber
    }
}
