import Foundation
import Testing

@testable import ProjectModel

@Suite("JSONValue")
struct JSONValueTests {
    @Test("Decodes every kind of JSON value")
    func decodesEveryKind() throws {
        let value = try decode(#"{"n":null,"b":true,"i":42,"d":1.5,"s":"hi","a":[1,"x"],"o":{"k":false}}"#)
        #expect(
            value
                == .object([
                    "n": .null,
                    "b": .bool(true),
                    "i": .int(42),
                    "d": .double(1.5),
                    "s": .string("hi"),
                    "a": .array([.int(1), .string("x")]),
                    "o": .object(["k": .bool(false)]),
                ])
        )
    }

    @Test("Keeps booleans and numbers apart")
    func keepsBooleansAndNumbersApart() throws {
        #expect(try decode("[true,1,0,false]") == .array([.bool(true), .int(1), .int(0), .bool(false)]))
    }

    @Test("Keeps integers exact beyond what a Double can hold")
    func keepsLargeIntegersExact() throws {
        // 2^53 + 1 is the smallest positive integer a Double can't represent.
        let json = "9007199254740993"
        #expect(try decode(json) == .int(9_007_199_254_740_993))
        #expect(try encode(decode(json)) == json)
    }

    @Test(
        "Writes back the same JSON it read",
        arguments: [
            #"{"a":[1,2.5,"x",null,true],"b":{"c":{"d":[]}},"e":-0.1}"#,
            "[]",
            "{}",
            #""text""#,
            "null",
        ]
    )
    func roundTrips(json: String) throws {
        #expect(try encode(decode(json)) == json)
    }
}

private func decode(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

private func encode(_ value: JSONValue) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try #require(String(bytes: encoder.encode(value), encoding: .utf8))
}
