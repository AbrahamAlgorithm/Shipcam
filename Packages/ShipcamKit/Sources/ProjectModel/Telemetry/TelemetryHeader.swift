/// The first line of `raw/cursor.jsonl`: what was captured, and how often the cursor
/// was sampled.
public struct TelemetryHeader: Equatable, Sendable {
    /// The newest format version this code reads and writes. Adding event types or
    /// keys keeps the version; changing the meaning of existing data raises it.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var sampleHz: Int
    public var source: Source

    public init(schemaVersion: Int = currentSchemaVersion, sampleHz: Int, source: Source) {
        self.schemaVersion = schemaVersion
        self.sampleHz = sampleHz
        self.source = source
    }

    /// The captured display, window or area.
    public struct Source: Codable, Equatable, Sendable {
        public var kind: CaptureKind
        public var pxWidth: Int
        public var pxHeight: Int
        /// Pixels per point: 2 on a Retina display.
        public var scale: Double

        public init(kind: CaptureKind, pxWidth: Int, pxHeight: Int, scale: Double) {
            self.kind = kind
            self.pxWidth = pxWidth
            self.pxHeight = pxHeight
            self.scale = scale
        }
    }
}

extension TelemetryHeader: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, schemaVersion, sampleHz, source
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        guard type == "header" else {
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "Expected \"header\", found \"\(type)\".")
        }
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        sampleHz = try container.decode(Int.self, forKey: .sampleHz)
        source = try container.decode(Source.self, forKey: .source)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("header", forKey: .type)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sampleHz, forKey: .sampleHz)
        try container.encode(source, forKey: .source)
    }
}
