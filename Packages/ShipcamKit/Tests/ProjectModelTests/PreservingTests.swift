import Foundation
import Testing

@testable import ProjectModel

// Stand-ins for project types: a document holding regions, each with an optional point.
private struct Point: Codable, Equatable {
    var x: Double
    var y: Double
}

private struct Region: Codable, Equatable {
    var start: Double
    var focus: Point?
}

private struct Doc: Codable, Equatable {
    var name: String
    var regions: [Preserving<Region>]
}

@Suite("Preserving")
struct PreservingTests {
    @Test("Unknown keys survive a load and save")
    func unknownKeysSurvive() throws {
        let saved = try resave(#"{"name":"Demo","regions":[],"future":{"deep":[1,{"x":true}]}}"#)
        #expect(saved["future"] == .object(["deep": .array([.int(1), .object(["x": .bool(true)])])]))
        #expect(saved["name"] == .string("Demo"))
    }

    @Test("Unknown keys inside array items stay with their item")
    func unknownKeysStayWithTheirItem() throws {
        let json = #"{"name":"Demo","regions":[{"start":1,"tag":"a"},{"start":2,"tag":"b"}]}"#
        let saved = try resave(json) { doc in
            doc.regions.remove(at: 0)
        }
        #expect(saved["regions"] == .array([.object(["start": .int(2), "tag": .string("b")])]))
    }

    @Test("Edits to known fields are saved")
    func editsAreSaved() throws {
        let saved = try resave(#"{"name":"Old","regions":[{"start":1}],"future":1}"#) { doc in
            doc.name = "New"
            doc.regions[0].start = 3
        }
        #expect(saved["name"] == .string("New"))
        #expect(saved["regions"] == .array([.object(["start": .int(3)])]))
        #expect(saved["future"] == .int(1))
    }

    @Test("A cleared optional stays cleared")
    func clearedOptionalStaysCleared() throws {
        let saved = try resave(#"{"name":"Demo","regions":[{"start":1,"focus":{"x":0.5,"y":0.5}}]}"#) { doc in
            doc.regions[0].focus = nil
        }
        #expect(saved["regions"] == .array([.object(["start": .int(1)])]))
    }

    @Test("An optional that was null can be set")
    func nullOptionalCanBeSet() throws {
        let saved = try resave(#"{"name":"Demo","regions":[{"start":1,"focus":null}]}"#) { doc in
            doc.regions[0].focus = Point(x: 0.25, y: 0.75)
        }
        let focus = JSONValue.object(["x": .double(0.25), "y": .double(0.75)])
        #expect(saved["regions"] == .array([.object(["start": .int(1), "focus": focus])]))
    }

    @Test("A value made in code has no unknown keys")
    func valueMadeInCode() throws {
        let doc = Preserving(Doc(name: "Fresh", regions: [Preserving(Region(start: 0, focus: nil))]))
        #expect(doc.unknownKeys.isEmpty)
        #expect(try encodeObject(doc) == ["name": .string("Fresh"), "regions": .array([.object(["start": .int(0)])])])
    }
}

/// Loads `json` as a document, applies `edit`, saves it, and returns the saved JSON object.
private func resave(_ json: String, edit: (inout Preserving<Doc>) -> Void = { _ in }) throws -> [String: JSONValue] {
    var doc = try JSONDecoder().decode(Preserving<Doc>.self, from: Data(json.utf8))
    edit(&doc)
    return try encodeObject(doc)
}

private func encodeObject(_ value: some Encodable) throws -> [String: JSONValue] {
    try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(value))
}
