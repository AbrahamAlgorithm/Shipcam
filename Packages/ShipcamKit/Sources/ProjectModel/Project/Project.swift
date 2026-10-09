import Foundation

/// The edit decisions for one recording, saved as `project.json`.
///
/// Every visual choice lives here and is applied when a frame is rendered; the raw
/// recording is never changed.
public typealias Project = Preserving<ProjectFields>

public struct ProjectFields: Codable, Equatable, Sendable {
    /// The newest `project.json` version this code reads and writes.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var source: Preserving<Source>

    /// Facts about the recording, so a project can be listed without opening its media.
    public struct Source: Codable, Equatable, Sendable {
        /// The recording's length in source time.
        public var durationSec: Double
    }
}

extension Preserving<ProjectFields> {
    /// A new project. `createdAt` is rounded down to a whole second, the precision
    /// `project.json` stores, so a saved project loads back equal.
    public init(name: String, createdAt: Date = .now, durationSec: Double = 0) {
        self.init(
            ProjectFields(
                schemaVersion: ProjectFields.currentSchemaVersion,
                id: UUID(),
                name: name,
                createdAt: Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down)),
                // Spelled out: inside this extension, a bare `Preserving` means
                // `Preserving<ProjectFields>`.
                source: Preserving<ProjectFields.Source>(ProjectFields.Source(durationSec: durationSec))
            )
        )
    }
}
