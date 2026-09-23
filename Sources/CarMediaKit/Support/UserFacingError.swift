import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CarMediaCore

/// Why a stream cannot be played with AVPlayer (and therefore never via AirPlay/CarPlay video).
public enum UnsupportedReason: String, Sendable, Hashable, Codable, CaseIterable {
    /// `.mkv` files.
    case matroska
    /// Raw progressive MPEG-TS (`.ts`) outside Xtream, where no HLS alternative can be requested.
    case rawTransportStream
    /// Other containers AVPlayer cannot open (`.avi`, `.wmv`, `.flv`, `.webm`).
    case container
    /// `rtsp://`, `rtmp://`, `rtp://`.
    case rtsp
    /// `udp://` multicast/unicast.
    case udp
    /// Any other non-HTTP scheme (`mms://`, `srt://`, …).
    case otherProtocol
}

/// A secret-free classification of failures, suitable for persisting and localizing in the UI.
///
/// Free-form error text can echo request URLs (and therefore Xtream passwords), so the app shows
/// these cases and, at most, a detail string passed through ``Redaction``.
public enum UserFacingError: Sendable, Hashable, Codable {
    /// Offline, timeout, DNS or TLS failure.
    case network
    /// The server answered with a non-success HTTP status.
    case httpStatus(Int)
    /// The server rejected the username or password.
    case authentication
    /// The address is a single media stream, not a channel list.
    case mediaStreamNotList
    /// The address does not contain a channel list.
    case notAChannelList
    /// The list parsed but contained no playable entries.
    case emptyPlaylist
    /// A server address, URL or form field is invalid.
    case invalidAddress
    /// The server response could not be understood.
    case unexpectedResponse
    /// Gzip-compressed content that must be decompressed first.
    case compressedData
    /// The stream format cannot be played.
    case unsupported(UnsupportedReason)
    /// The Xtream password is missing from secure storage.
    case missingPassword
    /// An imported file can no longer be opened.
    case fileUnavailable
    /// Anything else.
    case unknown

    /// Classifies an arbitrary error without keeping any of its text.
    public static func from(_ error: Error) -> UserFacingError {
        if let known = error as? UserFacingError { return known }
        if let carMedia = error as? CarMediaError {
            switch carMedia {
            case .notAChannelList(let kind):
                switch kind {
                case .hlsMediaPlaylist, .binaryMedia: return .mediaStreamNotList
                case .channelPlaylist, .unknown: return .notAChannelList
                }
            case .emptyPlaylist: return .emptyPlaylist
            case .invalidEncoding, .decoding, .invalidXMLTV: return .unexpectedResponse
            case .invalidURL: return .invalidAddress
            case .httpStatus(let code): return .httpStatus(code)
            case .transport: return .network
            case .authenticationFailed: return .authentication
            case .compressedDataNotSupported: return .compressedData
            }
        }
        if let store = error as? SourceStoreError {
            switch store {
            case .duplicateSource, .unknownSource: return .unknown
            case .missingPassword: return .missingPassword
            case .fileUnavailable: return .fileUnavailable
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return .network }
        // AVFoundation wraps network failures; look one level down.
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSURLErrorDomain {
            return .network
        }
        if nsError.domain == NSCocoaErrorDomain { return .fileUnavailable }
        return .unknown
    }

    /// A diagnostic string for logs/"details" UI, with every secret removed.
    public static func redactedDetail(of error: Error, secrets: [String]) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return Redaction.redact(text, secrets: secrets)
    }
}

extension UserFacingError: Error {}
