import Foundation

/// A `Codable` value that keeps the JSON keys its type doesn't know about.
///
/// Swift's synthesized `Codable` drops every key a type doesn't declare. If a newer
/// Shipcam adds a key to `project.json` and an older version opens and saves the
/// project, that key would be lost. `Preserving` keeps such keys in `unknownKeys`
/// and writes them back on save.
///
/// Wrap each object in a document that may gain keys, including the items of
/// arrays. Unknown keys then stay attached to the object they came from, even when
/// items are removed or reordered.
///
/// The wrapped type's properties read and write directly: `region.start` means
/// `region.fields.start`.
@dynamicMemberLookup
public struct Preserving<Fields: Codable> {
    /// The decoded value.
    public var fields: Fields
    /// The keys `Fields` doesn't decode, with their values as read.
    public var unknownKeys: [String: JSONValue]

    public init(_ fields: Fields) {
        self.fields = fields
        self.unknownKeys = [:]
    }

    public subscript<Value>(dynamicMember keyPath: WritableKeyPath<Fields, Value>) -> Value {
        get { fields[keyPath: keyPath] }
        set { fields[keyPath: keyPath] = newValue }
    }
}

extension Preserving: Codable {
    public init(from decoder: any Decoder) throws {
        fields = try Fields(from: decoder)

        // A key is known if `Fields` writes it back. An optional `Fields` property
        // is only written when it has a value, so a key whose value was null lands
        // in `unknownKeys`. That's harmless: see `encode(to:)`.
        let known = try Self.keysWritten(by: fields)
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !known.contains(key.stringValue) {
            unknown[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        unknownKeys = unknown
    }

    public func encode(to encoder: any Encoder) throws {
        // Unknown keys first, then `fields`. Both write into the same JSON object,
        // and a later write to a key replaces an earlier one, so if a key is in
        // both (a null that has since been set), the current value wins.
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownKeys {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try fields.encode(to: encoder)
    }

    private static func keysWritten(by fields: Fields) throws -> Set<String> {
        let data = try JSONEncoder().encode(fields)
        return Set(try JSONDecoder().decode([String: Ignored].self, from: data).keys)
    }
}

extension Preserving: Equatable where Fields: Equatable {}
extension Preserving: Hashable where Fields: Hashable {}
extension Preserving: Sendable where Fields: Sendable {}

/// Accepts any JSON value and keeps nothing, for reading only an object's keys.
private struct Ignored: Decodable {
    init(from decoder: any Decoder) throws {}
}

/// A coding key for any string, for keys that no type declares.
struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        nil
    }
}
