import Foundation

// Property wrappers that make `Codable` tolerant of the inconsistent JSON typical of Xtream panels:
// numbers as strings, "0"/"1" booleans, empty strings for numbers, `null`, and missing keys.
// A missing key or `null` yields `nil` instead of throwing.

/// Decodes `Int`, `"42"`, `42.0`, `"42.0"` or `true/false`; anything else (including `""`) becomes `nil`.
@propertyWrapper
public struct LossyInt: Codable, Sendable, Hashable {
    /// The decoded value.
    public var wrappedValue: Int?

    /// Wraps a value.
    public init(wrappedValue: Int?) { self.wrappedValue = wrappedValue }

    /// Decodes leniently; never throws for type mismatches.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = LossyScalar.decode(container).flatMap(\.intValue)
    }

    /// Encodes the value or `null`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

/// Decodes `Double`, `Int`, or numeric strings (`"7.5"`, `"7,5"`); anything else becomes `nil`.
@propertyWrapper
public struct LossyDouble: Codable, Sendable, Hashable {
    /// The decoded value.
    public var wrappedValue: Double?

    /// Wraps a value.
    public init(wrappedValue: Double?) { self.wrappedValue = wrappedValue }

    /// Decodes leniently; never throws for type mismatches.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = LossyScalar.decode(container).flatMap(\.doubleValue)
    }

    /// Encodes the value or `null`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

/// Decodes `true/false`, `0/1`, `"0"/"1"`, `"true"/"false"`, `"yes"/"no"`; anything else becomes `nil`.
@propertyWrapper
public struct LossyBool: Codable, Sendable, Hashable {
    /// The decoded value.
    public var wrappedValue: Bool?

    /// Wraps a value.
    public init(wrappedValue: Bool?) { self.wrappedValue = wrappedValue }

    /// Decodes leniently; never throws for type mismatches.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = LossyScalar.decode(container).flatMap(\.boolValue)
    }

    /// Encodes the value or `null`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

/// Decodes strings, numbers and booleans as text. Empty strings are kept as `""`.
@propertyWrapper
public struct LossyString: Codable, Sendable, Hashable {
    /// The decoded value.
    public var wrappedValue: String?

    /// Wraps a value.
    public init(wrappedValue: String?) { self.wrappedValue = wrappedValue }

    /// Decodes leniently; never throws for type mismatches.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = LossyScalar.decode(container).flatMap(\.stringValue)
    }

    /// Encodes the value or `null`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

/// Decodes any `Codable` value, or `nil` if the JSON has a different shape
/// (e.g. Xtream returning `[]` where an object is expected).
@propertyWrapper
public struct LossyValue<Value: Codable & Sendable & Hashable>: Codable, Sendable, Hashable {
    /// The decoded value.
    public var wrappedValue: Value?

    /// Wraps a value.
    public init(wrappedValue: Value?) { self.wrappedValue = wrappedValue }

    /// Decodes leniently; never throws for type mismatches.
    public init(from decoder: Decoder) throws {
        wrappedValue = try? Value(from: decoder)
    }

    /// Encodes the value or `null`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

/// An array decoder that skips elements that fail to decode instead of failing the whole array.
public struct LossyList<Element: Decodable>: Decodable {
    /// Successfully decoded elements, in order.
    public var elements: [Element]
    /// Number of elements that were skipped.
    public var skippedCount: Int

    /// Decodes an array, skipping bad elements.
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        var skipped = 0
        if let count = container.count { elements.reserveCapacity(count) }
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(SkipValue.self)
                skipped += 1
            }
        }
        self.elements = elements
        self.skippedCount = skipped
    }

    private struct SkipValue: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

// Missing keys decode to `nil` rather than throwing `keyNotFound`.
extension KeyedDecodingContainer {
    /// Missing-key tolerant decoding for ``LossyInt``.
    public func decode(_ type: LossyInt.Type, forKey key: Key) throws -> LossyInt {
        (try? decodeIfPresent(type, forKey: key)).flatMap { $0 } ?? LossyInt(wrappedValue: nil)
    }

    /// Missing-key tolerant decoding for ``LossyDouble``.
    public func decode(_ type: LossyDouble.Type, forKey key: Key) throws -> LossyDouble {
        (try? decodeIfPresent(type, forKey: key)).flatMap { $0 } ?? LossyDouble(wrappedValue: nil)
    }

    /// Missing-key tolerant decoding for ``LossyBool``.
    public func decode(_ type: LossyBool.Type, forKey key: Key) throws -> LossyBool {
        (try? decodeIfPresent(type, forKey: key)).flatMap { $0 } ?? LossyBool(wrappedValue: nil)
    }

    /// Missing-key tolerant decoding for ``LossyString``.
    public func decode(_ type: LossyString.Type, forKey key: Key) throws -> LossyString {
        (try? decodeIfPresent(type, forKey: key)).flatMap { $0 } ?? LossyString(wrappedValue: nil)
    }

    /// Missing-key tolerant decoding for ``LossyValue``.
    public func decode<V>(_ type: LossyValue<V>.Type, forKey key: Key) throws -> LossyValue<V> {
        (try? decodeIfPresent(type, forKey: key)).flatMap { $0 } ?? LossyValue(wrappedValue: nil)
    }
}

/// A JSON scalar decoded without committing to a type.
enum LossyScalar {
    case int(Int)
    case double(Double)
    case bool(Bool)
    case string(String)

    static func decode(_ container: SingleValueDecodingContainer) -> LossyScalar? {
        if container.decodeNil() { return nil }
        if let value = try? container.decode(Int.self) { return .int(value) }
        if let value = try? container.decode(Double.self) { return .double(value) }
        if let value = try? container.decode(Bool.self) { return .bool(value) }
        if let value = try? container.decode(String.self) { return .string(value) }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .double(let v): return v.isFinite && abs(v) < 9e18 ? Int(v) : nil
        case .bool(let v): return v ? 1 : 0
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespaces)
            if let v = Int(t) { return v }
            if let d = Double(t), d.isFinite, abs(d) < 9e18 { return Int(d) }
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .int(let v): return Double(v)
        case .double(let v): return v
        case .bool: return nil
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            return Double(t)
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let v): return v
        case .int(let v): return v != 0
        case .double(let v): return v != 0
        case .string(let s):
            switch s.trimmingCharacters(in: .whitespaces).lowercased() {
            case "1", "true", "yes", "y", "on": return true
            case "0", "false", "no", "n", "off", "": return false
            default: return nil
            }
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let v): return String(v)
        case .double(let v):
            return v.rounded() == v && abs(v) < 1e15 ? String(Int(v)) : String(v)
        case .bool(let v): return v ? "1" : "0"
        }
    }
}
