import Foundation

/// The contents of a `raw/cursor.jsonl` file.
///
/// Reading is forgiving about events and strict about the header. A damaged line,
/// such as the half-written last line a crash leaves behind, is skipped and
/// reported, so a recording is never lost to one bad line. Without a valid header,
/// no position in the file can be interpreted, so that's an error.
public struct TelemetryLog: Equatable, Sendable {
    public var header: TelemetryHeader
    /// Sorted by time. Events with equal times keep their order in the file.
    public var events: [TelemetryEvent]
    /// Lines that couldn't be read. The rest of the file is still used.
    public var skippedLines: [SkippedLine]

    public struct SkippedLine: Equatable, Sendable {
        /// Counting from 1, the header being line 1.
        public var lineNumber: Int
        public var reason: Reason

        public enum Reason: Equatable, Sendable {
            /// An event type this version doesn't know, probably from a newer Shipcam.
            case unknownType(String)
            /// Not valid JSON, or missing fields.
            case unreadable
        }
    }

    public enum ReadError: Error, Equatable {
        /// The first line isn't a valid header.
        case missingHeader
        /// The file was written in a newer format than this version reads.
        case unsupportedSchemaVersion(Int)
    }
}

extension TelemetryLog {
    public init(contentsOf url: URL) throws {
        try self.init(jsonl: Data(contentsOf: url))
    }

    public init(jsonl data: Data) throws {
        let decoder = JSONDecoder()
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)

        // Check the version before decoding the whole header: a newer format may have
        // changed the header too, and "unsupported version" is the clearer error.
        guard let first = lines.first,
            let probe = try? decoder.decode(VersionProbe.self, from: first),
            probe.type == "header"
        else { throw ReadError.missingHeader }
        guard probe.schemaVersion <= TelemetryHeader.currentSchemaVersion else {
            throw ReadError.unsupportedSchemaVersion(probe.schemaVersion)
        }
        guard let header = try? decoder.decode(TelemetryHeader.self, from: first) else {
            throw ReadError.missingHeader
        }

        var events: [TelemetryEvent] = []
        var skipped: [SkippedLine] = []
        for (index, line) in lines.enumerated().dropFirst() where !line.isEmpty {
            do {
                events.append(try decoder.decode(TelemetryEvent.self, from: line))
            } catch let error as TelemetryEvent.UnknownType {
                skipped.append(SkippedLine(lineNumber: index + 1, reason: .unknownType(error.type)))
            } catch {
                skipped.append(SkippedLine(lineNumber: index + 1, reason: .unreadable))
            }
        }

        // Different sources (the event tap, the cursor sampler, the bubble) can log
        // slightly out of order. Sorting by (time, line) keeps equal times in file
        // order, so a down and an up logged in the same instant stay in sequence.
        self.header = header
        self.events = events.enumerated()
            .sorted { ($0.element.t, $0.offset) < ($1.element.t, $1.offset) }
            .map(\.element)
        self.skippedLines = skipped
    }
}

private struct VersionProbe: Decodable {
    var type: String
    var schemaVersion: Int
}
