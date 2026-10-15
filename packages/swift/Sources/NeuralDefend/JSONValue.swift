import Foundation

/// A decoded JSON value, used for the redacted `raw` wire envelope.
///
/// Numbers are stored as `Double`, which represents every value the API documents exactly.
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// The member named `key` when this value is an object.
    public subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { return members[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var isNull: Bool { self == .null }

    /// Parses UTF-8 JSON. Returns `nil` for malformed input.
    static func parse(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Deep copy with every occurrence of `secret` in string values replaced.
    func redacting(_ secret: String) -> JSONValue {
        switch self {
        case .string(let value):
            return .string(redact(value, secret))
        case .array(let values):
            return .array(values.map { $0.redacting(secret) })
        case .object(let members):
            return .object(members.mapValues { $0.redacting(secret) })
        case .null, .bool, .number:
            return self
        }
    }
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// Replaces every occurrence of `secret` in `value`.
func redact(_ value: String, _ secret: String) -> String {
    secret.isEmpty ? value : value.replacingOccurrences(of: secret, with: "[REDACTED]")
}
