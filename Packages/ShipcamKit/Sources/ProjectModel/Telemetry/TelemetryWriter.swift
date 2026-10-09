import Foundation

/// Writes `raw/cursor.jsonl`, one JSON object per line.
///
/// Each line is written with a single call as soon as it's appended. If the app
/// crashes mid-recording, at most the line being written is damaged, and
/// `TelemetryLog` skips it.
///
/// Not thread-safe: give each writer a single owner, such as one serial queue.
public final class TelemetryWriter {
    private let handle: FileHandle
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// Creates the file and writes the header. Throws if a file already exists at
    /// `url`: raw recording files are written once and never replaced.
    public init(creatingFileAt url: URL, header: TelemetryHeader) throws {
        try Data().write(to: url, options: .withoutOverwriting)
        handle = try FileHandle(forWritingTo: url)
        try write(header)
    }

    public func append(_ event: TelemetryEvent) throws {
        try write(event)
    }

    /// Flushes the file to disk and closes it.
    public func close() throws {
        try handle.synchronize()
        try handle.close()
    }

    private func write(_ value: some Encodable) throws {
        var line = try encoder.encode(value)
        line.append(UInt8(ascii: "\n"))
        try handle.write(contentsOf: line)
    }
}
