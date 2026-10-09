import Foundation
import Testing

@testable import ProjectModel

@Suite("ProjectBundle")
struct ProjectBundleTests {
    @Test("Creating a bundle makes the folder layout")
    func createsLayout() throws {
        try withTemporaryFolder { folder in
            let bundle = try ProjectBundle.create(
                at: folder.appending(path: "Demo.shipcam"), project: Project(name: "Demo"))

            for path in ["project.json", "raw", "assets", "cache", ".gitignore"] {
                #expect(FileManager.default.fileExists(atPath: bundle.url.appending(path: path).path), "\(path)")
            }
            #expect(try String(contentsOf: bundle.url.appending(path: ".gitignore"), encoding: .utf8) == "cache/\n")
            #expect(bundle.url(for: .cursor) == bundle.url.appending(path: "raw/cursor.jsonl"))
        }
    }

    @Test("A created project loads back unchanged")
    func loadsBackUnchanged() throws {
        try withTemporaryFolder { folder in
            let project = Project(name: "Demo", createdAt: Date(timeIntervalSince1970: 1_800_000_000.75))
            let bundle = try ProjectBundle.create(at: folder.appending(path: "Demo.shipcam"), project: project)
            #expect(try bundle.loadProject() == project)
        }
    }

    @Test("Writes project.json pretty-printed, with sorted keys and ISO 8601 dates")
    func writesTheExactFormat() throws {
        try withTemporaryFolder { folder in
            var project = Project(name: "Onboarding demo", createdAt: Date(timeIntervalSince1970: 1_791_489_600))
            project.id = try #require(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"))
            project.source.durationSec = 94.5
            let bundle = try ProjectBundle.create(at: folder.appending(path: "Demo.shipcam"), project: project)

            #expect(
                try String(contentsOf: bundle.projectFileURL, encoding: .utf8) == """
                    {
                      "createdAt" : "2026-10-08T20:00:00Z",
                      "id" : "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                      "name" : "Onboarding demo",
                      "schemaVersion" : 1,
                      "source" : {
                        "durationSec" : 94.5
                      }
                    }
                    """
            )
        }
    }

    @Test("Saving keeps keys from a newer version and applies edits")
    func savingKeepsUnknownKeys() throws {
        try withTemporaryFolder { folder in
            let bundle = try ProjectBundle.create(
                at: folder.appending(path: "Demo.shipcam"), project: Project(name: "Old"))
            try Data(
                """
                {"schemaVersion":1,"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","name":"Old",
                 "createdAt":"2026-10-08T20:00:00Z","source":{"durationSec":10,"frameCount":600},
                 "grade":{"vignette":0.3}}
                """.utf8
            ).write(to: bundle.projectFileURL)

            var project = try bundle.loadProject()
            project.name = "New"
            try bundle.save(project)

            let saved = try JSONDecoder().decode(
                [String: JSONValue].self, from: Data(contentsOf: bundle.projectFileURL))
            #expect(saved["name"] == .string("New"))
            #expect(saved["grade"] == .object(["vignette": .double(0.3)]))
            #expect(saved["source"] == .object(["durationSec": .int(10), "frameCount": .int(600)]))
        }
    }

    @Test("Refuses to create a bundle where something already exists")
    func refusesToOverwrite() throws {
        try withTemporaryFolder { folder in
            let url = folder.appending(path: "Demo.shipcam")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            try Data("mine".utf8).write(to: url.appending(path: "notes.txt"))

            #expect(throws: (any Error).self) {
                try ProjectBundle.create(at: url, project: Project(name: "Demo"))
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: url.path) == ["notes.txt"])
        }
    }

    @Test("Refuses to open a project from a newer version")
    func refusesNewerSchemaVersion() throws {
        try withTemporaryFolder { folder in
            let bundle = try ProjectBundle.create(
                at: folder.appending(path: "Demo.shipcam"), project: Project(name: "Demo"))
            try Data(#"{"schemaVersion":2,"name":"From the future"}"#.utf8).write(to: bundle.projectFileURL)

            #expect(throws: ProjectBundle.OpenError.unsupportedSchemaVersion(2)) {
                try bundle.loadProject()
            }
        }
    }
}

/// Runs `body` with a fresh, empty folder that's deleted afterwards.
private func withTemporaryFolder(_ body: (URL) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "ProjectBundleTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(folder)
}
