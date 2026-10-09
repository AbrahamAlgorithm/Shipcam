import Foundation
import Testing

@testable import ProjectModel

private let header = TelemetryHeader(
    schemaVersion: 1,
    sampleHz: 120,
    source: .init(kind: .display, pxWidth: 3024, pxHeight: 1964, scale: 2)
)

@Suite("Telemetry")
struct TelemetryTests {
    @Test("Reads every event type in the documented format")
    func readsTheDocumentedFormat() throws {
        let log = try TelemetryLog(
            jsonl: Data(
                """
                {"schemaVersion":1,"type":"header","sampleHz":120,"source":{"kind":"display","pxWidth":3024,"pxHeight":1964,"scale":2}}
                {"t":0.008,"type":"move","x":0.512,"y":0.430,"visible":true,"cursor":"arrow"}
                {"t":1.244,"type":"down","button":"left","x":0.611,"y":0.218}
                {"t":1.302,"type":"up","button":"left","x":0.611,"y":0.218}
                {"t":2.010,"type":"scroll","dx":0,"dy":-12.5,"x":0.6,"y":0.5}
                {"t":3.400,"type":"key","phase":"down","class":"char","mods":[]}
                {"t":3.402,"type":"key","phase":"down","class":"combo","mods":["cmd","shift"],"chars":"p"}
                {"t":3.410,"type":"caret","x":0.33,"y":0.71,"w":0.002,"h":0.02}
                {"t":4.000,"type":"cursorImage","id":"c_7f3a","hotspot":[0.25,0.1]}
                {"t":5.2,"type":"bubble","x":0.82,"y":0.78,"size":"medium","shape":"circle","visible":true}
                """.utf8))

        #expect(log.header == header)
        #expect(log.skippedLines.isEmpty)
        #expect(
            log.events == [
                .init(t: 0.008, kind: .move(.init(x: 0.512, y: 0.43, visible: true, cursor: "arrow"))),
                .init(t: 1.244, kind: .down(.init(button: .left, x: 0.611, y: 0.218))),
                .init(t: 1.302, kind: .up(.init(button: .left, x: 0.611, y: 0.218))),
                .init(t: 2.01, kind: .scroll(.init(dx: 0, dy: -12.5, x: 0.6, y: 0.5))),
                .init(t: 3.4, kind: .key(.init(phase: .down, class: .char, mods: [], chars: nil))),
                .init(t: 3.402, kind: .key(.init(phase: .down, class: .combo, mods: [.cmd, .shift], chars: "p"))),
                .init(t: 3.41, kind: .caret(.init(x: 0.33, y: 0.71, w: 0.002, h: 0.02))),
                .init(t: 4, kind: .cursorImage(.init(id: "c_7f3a", hotspot: SIMD2(0.25, 0.1)))),
                .init(t: 5.2, kind: .bubble(.init(x: 0.82, y: 0.78, size: .medium, shape: .circle, visible: true))),
            ]
        )
    }

    @Test("Writes one compact JSON object per line, keys sorted")
    func writesTheExactFormat() throws {
        let text = try written([.init(t: 1.25, kind: .down(.init(button: .left, x: 0.5, y: 0.25)))])
        #expect(
            text == """
                {"sampleHz":120,"schemaVersion":1,"source":{"kind":"display","pxHeight":1964,"pxWidth":3024,"scale":2},"type":"header"}
                {"button":"left","t":1.25,"type":"down","x":0.5,"y":0.25}

                """
        )
    }

    @Test("Reads back exactly what the writer wrote")
    func roundTrips() throws {
        let events: [TelemetryEvent] = [
            .init(t: 0.1, kind: .move(.init(x: 0.1, y: 0.2, visible: false, cursor: "iBeam"))),
            .init(t: 0.2, kind: .down(.init(button: .right, x: 0.3, y: 0.4))),
            .init(t: 0.3, kind: .up(.init(button: .other, x: 0.3, y: 0.4))),
            .init(t: 0.4, kind: .scroll(.init(dx: 1.5, dy: -3, x: 0.5, y: 0.5))),
            .init(t: 0.5, kind: .key(.init(phase: .up, class: .enter, mods: [.ctrl, .opt, .fn], chars: nil))),
            .init(t: 0.6, kind: .caret(.init(x: 0.1, y: 0.9, w: 0.01, h: 0.02))),
            .init(t: 0.7, kind: .cursorImage(.init(id: "c_1", hotspot: SIMD2(0.5, 0.5)))),
            .init(t: 0.8, kind: .bubble(.init(x: 0.9, y: 0.1, size: .large, shape: .roundedRect, visible: false))),
        ]
        let log = try TelemetryLog(jsonl: Data(written(events).utf8))
        #expect(log.header == header)
        #expect(log.events == events)
    }

    @Test("Skips an incomplete last line, as a crash leaves behind")
    func skipsIncompleteLastLine() throws {
        let log = try TelemetryLog(
            jsonl: Data(
                """
                \(try written([.init(t: 1, kind: .move(.init(x: 0.5, y: 0.5, visible: true, cursor: "arrow")))]))\
                {"t":2,"type":"mo
                """.utf8))
        #expect(log.events.map(\.t) == [1])
        #expect(log.skippedLines.map(\.lineNumber) == [3])
    }

    @Test("Skips a damaged line in the middle and keeps the rest")
    func skipsDamagedLine() throws {
        let log = try TelemetryLog(
            jsonl: Data(
                """
                {"schemaVersion":1,"type":"header","sampleHz":120,"source":{"kind":"area","pxWidth":800,"pxHeight":600,"scale":1}}
                {"t":1,"type":"down","button":"left","x":0.5,"y":0.5}
                {"t":2,"type":"down","button":"left","x":
                {"t":3,"type":"up","button":"left","x":0.5,"y":0.5}
                """.utf8))
        #expect(log.events.map(\.t) == [1, 3])
        #expect(log.skippedLines.map(\.lineNumber) == [3])
    }

    @Test("Skips event types from a newer version and names them")
    func skipsUnknownEventTypes() throws {
        let log = try TelemetryLog(
            jsonl: Data(
                """
                \(try written([]))\
                {"t":1,"type":"gesture","x":0.5,"y":0.5}
                """.utf8))
        #expect(log.events.isEmpty)
        #expect(log.skippedLines == [.init(lineNumber: 2, reason: .unknownType("gesture"))])
    }

    @Test("Returns events sorted by time, keeping file order for equal times")
    func sortsByTime() throws {
        let log = try TelemetryLog(
            jsonl: Data(
                """
                \(try written([]))\
                {"t":2,"type":"down","button":"left","x":0.5,"y":0.5}
                {"t":1,"type":"down","button":"left","x":0.1,"y":0.1}
                {"t":1,"type":"up","button":"left","x":0.1,"y":0.1}
                """.utf8))
        #expect(log.events.map(\.t) == [1, 1, 2])
        #expect(log.events.first?.kind == .down(.init(button: .left, x: 0.1, y: 0.1)))
    }

    @Test(
        "Rejects a file whose first line isn't a header",
        arguments: ["", #"{"t":1,"type":"up","button":"left","x":0,"y":0}"#])
    func rejectsMissingHeader(text: String) {
        #expect(throws: TelemetryLog.ReadError.missingHeader) {
            try TelemetryLog(jsonl: Data(text.utf8))
        }
    }

    @Test("Rejects a newer schema version")
    func rejectsNewerSchemaVersion() {
        let text = """
            {"schemaVersion":2,"type":"header","sampleHz":120,"source":{"kind":"display","pxWidth":1,"pxHeight":1,"scale":1}}
            """
        #expect(throws: TelemetryLog.ReadError.unsupportedSchemaVersion(2)) {
            try TelemetryLog(jsonl: Data(text.utf8))
        }
    }

    @Test("Refuses to overwrite an existing file")
    func refusesToOverwrite() throws {
        let url = temporaryFileURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("keep me".utf8).write(to: url)

        #expect(throws: (any Error).self) {
            try TelemetryWriter(creatingFileAt: url, header: header)
        }
        #expect(try Data(contentsOf: url) == Data("keep me".utf8))
    }
}

/// Writes `events` with a `TelemetryWriter` and returns the file's text.
private func written(_ events: [TelemetryEvent]) throws -> String {
    let url = temporaryFileURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let writer = try TelemetryWriter(creatingFileAt: url, header: header)
    for event in events {
        try writer.append(event)
    }
    try writer.close()
    return try #require(String(bytes: Data(contentsOf: url), encoding: .utf8))
}

private func temporaryFileURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("telemetry-\(UUID().uuidString).jsonl")
}
