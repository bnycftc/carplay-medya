import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Result of parsing an XMLTV document.
public struct XMLTVDocument: Sendable {
    /// `<channel>` elements in document order.
    public var channels: [EPGChannel]
    /// `<programme>` elements in document order.
    public var programmes: [Programme]
    /// Programmes dropped because of a missing channel or unparsable start time.
    public var skippedProgrammeCount: Int
    /// Parser error message if the document was truncated or malformed after some content was read.
    public var parseError: String?

    /// Builds an ``EPGStore`` from the parsed content.
    public func makeStore() -> EPGStore {
        EPGStore(channels: channels, programmes: programmes)
    }
}

/// Summary returned by the callback-based streaming API.
public struct XMLTVParseSummary: Sendable, Equatable {
    /// Number of channels delivered.
    public var channelCount: Int
    /// Number of programmes delivered.
    public var programmeCount: Int
    /// Programmes dropped because of a missing channel or unparsable start time.
    public var skippedProgrammeCount: Int
    /// Parser error message, if parsing stopped early.
    public var parseError: String?
}

/// Streaming (SAX) XMLTV parser built on Foundation's `XMLParser`.
///
/// Memory stays flat regardless of file size when using ``parse(stream:onChannel:onProgramme:)``
/// or ``parse(fileURL:onChannel:onProgramme:)``: elements are delivered one by one and never
/// held as a DOM.
///
/// Gzip: XMLTV guides are often served as `.xml.gz`. Decompression is the caller's job
/// (HTTP `Content-Encoding: gzip` is already undone by `URLSession`; for `.gz` files use
/// Apple's Compression framework in the app). Gzip input is rejected with
/// ``CarMediaError/compressedDataNotSupported``.
///
/// Times use `yyyyMMddHHmmss ±HHMM`; a missing zone is treated as UTC. A missing `stop`
/// is filled by ``EPGStore`` from the next programme's start.
public enum XMLTVParser {
    /// Parses an in-memory document and collects everything.
    public static func parse(data: Data) throws -> XMLTVDocument {
        if TextDecoding.isGzip(data) { throw CarMediaError.compressedDataNotSupported }
        return try collect(XMLParser(data: data))
    }

    /// Parses a file from disk, collecting everything.
    public static func parse(fileURL: URL) throws -> XMLTVDocument {
        try rejectGzipFile(fileURL)
        guard let stream = InputStream(url: fileURL) else {
            throw CarMediaError.invalidXMLTV("cannot open file")
        }
        return try collect(XMLParser(stream: stream))
    }

    /// Streams a file from disk, delivering elements through callbacks without accumulating them.
    @discardableResult
    public static func parse(
        fileURL: URL,
        onChannel: @escaping (EPGChannel) -> Void,
        onProgramme: @escaping (Programme) -> Void
    ) throws -> XMLTVParseSummary {
        try rejectGzipFile(fileURL)
        guard let stream = InputStream(url: fileURL) else {
            throw CarMediaError.invalidXMLTV("cannot open file")
        }
        return try parse(stream: stream, onChannel: onChannel, onProgramme: onProgramme)
    }

    /// Streams from an `InputStream`, delivering elements through callbacks without accumulating them.
    @discardableResult
    public static func parse(
        stream: InputStream,
        onChannel: @escaping (EPGChannel) -> Void,
        onProgramme: @escaping (Programme) -> Void
    ) throws -> XMLTVParseSummary {
        try run(XMLParser(stream: stream), onChannel: onChannel, onProgramme: onProgramme)
    }

    // MARK: Internals

    private static func collect(_ parser: XMLParser) throws -> XMLTVDocument {
        var channels: [EPGChannel] = []
        var programmes: [Programme] = []
        let summary = try run(parser, onChannel: { channels.append($0) }, onProgramme: { programmes.append($0) })
        return XMLTVDocument(
            channels: channels,
            programmes: programmes,
            skippedProgrammeCount: summary.skippedProgrammeCount,
            parseError: summary.parseError
        )
    }

    private static func run(
        _ parser: XMLParser,
        onChannel: @escaping (EPGChannel) -> Void,
        onProgramme: @escaping (Programme) -> Void
    ) throws -> XMLTVParseSummary {
        let delegate = XMLTVParserDelegate(onChannel: onChannel, onProgramme: onProgramme)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        let ok = parser.parse()
        var errorMessage: String? = ok ? nil : (parser.parserError.map { String(describing: $0) } ?? "unknown parse error")
        // Some libxml2 builds report success for truncated input; a missing </tv> is the reliable signal.
        if ok, delegate.sawRoot, !delegate.sawRootEnd {
            errorMessage = "document truncated (missing </tv>)"
        }
        let delivered = delegate.channelCount + delegate.programmeCount
        if !ok, delivered == 0 {
            throw CarMediaError.invalidXMLTV(errorMessage ?? "unknown parse error")
        }
        if ok, !delegate.sawRoot {
            throw CarMediaError.invalidXMLTV("missing <tv> root element")
        }
        return XMLTVParseSummary(
            channelCount: delegate.channelCount,
            programmeCount: delegate.programmeCount,
            skippedProgrammeCount: delegate.skippedProgrammeCount,
            parseError: errorMessage
        )
    }

    private static func rejectGzipFile(_ url: URL) throws {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw CarMediaError.invalidXMLTV("cannot open file")
        }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: 2)
        if TextDecoding.isGzip(head) { throw CarMediaError.compressedDataNotSupported }
    }
}

/// SAX delegate that assembles channels and programmes.
private final class XMLTVParserDelegate: NSObject, XMLParserDelegate {
    private let onChannel: (EPGChannel) -> Void
    private let onProgramme: (Programme) -> Void

    private(set) var channelCount = 0
    private(set) var programmeCount = 0
    private(set) var skippedProgrammeCount = 0
    private(set) var sawRoot = false
    private(set) var sawRootEnd = false

    private var text = ""
    private var capturing = false

    // <channel>
    private var inChannel = false
    private var channelID: String?
    private var displayNames: [String] = []
    private var channelIcon: URL?

    // <programme>
    private var inProgramme = false
    private var programmeChannel: String?
    private var programmeStart: Date?
    private var programmeStop: Date?
    private var title: String?
    private var subtitle: String?
    private var desc: String?
    private var categories: [String] = []
    private var episodeNumber: String?
    private var episodeIsOnscreen = false
    private var episodeSystem: String?
    private var programmeIcon: URL?

    init(onChannel: @escaping (EPGChannel) -> Void, onProgramme: @escaping (Programme) -> Void) {
        self.onChannel = onChannel
        self.onProgramme = onProgramme
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "tv":
            sawRoot = true
        case "channel" where !inProgramme:
            inChannel = true
            channelID = attributeDict["id"]
            displayNames = []
            channelIcon = nil
        case "programme":
            inProgramme = true
            programmeChannel = attributeDict["channel"]
            programmeStart = attributeDict["start"].flatMap(DateParsing.xmltv)
            programmeStop = attributeDict["stop"].flatMap(DateParsing.xmltv)
            title = nil
            subtitle = nil
            desc = nil
            categories = []
            episodeNumber = nil
            episodeIsOnscreen = false
            programmeIcon = nil
        case "display-name", "title", "sub-title", "desc", "category":
            text = ""
            capturing = true
        case "episode-num":
            text = ""
            capturing = true
            episodeSystem = attributeDict["system"]
        case "icon":
            let url = attributeDict["src"].flatMap { PercentEncoding.lenientURL($0) }
            if inProgramme { programmeIcon = programmeIcon ?? url } else if inChannel { channelIcon = channelIcon ?? url }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { text += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if capturing { text += String(decoding: CDATABlock, as: UTF8.self) }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = capturing ? text.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        switch elementName {
        case "tv":
            sawRootEnd = true
        case "display-name":
            if inChannel, !value.isEmpty { displayNames.append(value) }
        case "title":
            if inProgramme, title == nil, !value.isEmpty { title = value }
        case "sub-title":
            if inProgramme, subtitle == nil, !value.isEmpty { subtitle = value }
        case "desc":
            if inProgramme, desc == nil, !value.isEmpty { desc = value }
        case "category":
            if inProgramme, !value.isEmpty { categories.append(value) }
        case "episode-num":
            if inProgramme, !value.isEmpty {
                let onscreen = episodeSystem?.lowercased() == "onscreen"
                if episodeNumber == nil || (onscreen && !episodeIsOnscreen) {
                    episodeNumber = value
                    episodeIsOnscreen = onscreen
                }
            }
        case "channel" where inChannel:
            inChannel = false
            if let channelID, !channelID.isEmpty {
                channelCount += 1
                onChannel(EPGChannel(id: channelID, displayNames: displayNames, iconURL: channelIcon))
            }
        case "programme":
            inProgramme = false
            if let channel = programmeChannel, !channel.isEmpty, let start = programmeStart {
                programmeCount += 1
                onProgramme(Programme(
                    channelID: channel,
                    start: start,
                    stop: programmeStop ?? start,
                    title: title ?? "",
                    subtitle: subtitle,
                    description: desc,
                    categories: categories,
                    episodeNumber: episodeNumber,
                    iconURL: programmeIcon
                ))
            } else {
                skippedProgrammeCount += 1
            }
        default:
            break
        }
        capturing = false
        text = ""
    }
}
