import Foundation

/// A `.shipcam` project: a folder that Finder shows as a single file.
///
///     Demo.shipcam/
///       project.json   edit decisions (`Project`)
///       raw/           the recording, written once and never changed
///       assets/        images, music, fonts and LUTs the user adds
///       cache/         thumbnails, waveforms and other data that can be rebuilt
public struct ProjectBundle: Equatable, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var projectFileURL: URL { url.appending(path: "project.json") }
    public var rawFolderURL: URL { url.appending(path: "raw") }
    public var assetsFolderURL: URL { url.appending(path: "assets") }
    public var cacheFolderURL: URL { url.appending(path: "cache") }

    /// The files a recording writes into `raw/`.
    public enum RawFile: String, CaseIterable, Sendable {
        case screen = "screen.mov"
        case cursor = "cursor.jsonl"
        case mic = "mic.m4a"
        case system = "system.m4a"
        case camera = "camera.mov"
        case meta = "meta.json"
    }

    public func url(for file: RawFile) -> URL {
        rawFolderURL.appending(path: file.rawValue)
    }

    public enum OpenError: Error, Equatable {
        /// Saved by a newer Shipcam. Opening and saving it here could lose data.
        case unsupportedSchemaVersion(Int)
    }
}

extension ProjectBundle {
    /// Creates the bundle's folders and writes `project`. Throws without touching
    /// anything if a file or folder already exists at `url`.
    @discardableResult
    public static func create(at url: URL, project: Project) throws -> ProjectBundle {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        let bundle = ProjectBundle(url: url)
        do {
            for folder in [bundle.rawFolderURL, bundle.assetsFolderURL, bundle.cacheFolderURL] {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
            }
            // For anyone keeping projects in git: cache/ can be rebuilt, so leave it out.
            try Data("cache/\n".utf8).write(to: url.appending(path: ".gitignore"))
            try bundle.save(project)
        } catch {
            // We created this folder, so don't leave a half-made bundle behind.
            try? fileManager.removeItem(at: url)
            throw error
        }
        return bundle
    }

    public func loadProject() throws -> Project {
        let data = try Data(contentsOf: projectFileURL)
        // Check the version first: a newer format may not decode at all, and "saved
        // by a newer version" is the clearer error.
        let version = try JSONDecoder().decode(VersionProbe.self, from: data).schemaVersion
        guard version <= ProjectFields.currentSchemaVersion else {
            throw OpenError.unsupportedSchemaVersion(version)
        }
        return try ProjectJSON.decoder().decode(Project.self, from: data)
    }

    /// Writes `project.json` atomically: to a temporary file that then replaces the
    /// old one, so a crash mid-save leaves the previous version intact.
    public func save(_ project: Project) throws {
        try ProjectJSON.encoder().encode(project).write(to: projectFileURL, options: .atomic)
    }
}

private struct VersionProbe: Decodable {
    var schemaVersion: Int
}

/// JSON settings for `project.json`, chosen so the file reads well and diffs cleanly.
enum ProjectJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
