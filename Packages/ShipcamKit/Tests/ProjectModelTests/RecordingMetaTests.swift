import Foundation
import Testing

@testable import ProjectModel

/// Started at host time 1000, paused from 1030 to 1034 and from 1050 to 1052, stopped at 1100.
private let meta = RecordingMeta(
    appVersion: "0.1.0",
    capture: .init(
        kind: .display, displayID: 1, displayName: "Built-in Retina Display",
        rect: .init(x: 0, y: 0, w: 1512, h: 982), scale: 2),
    startHostTime: 1000,
    stopHostTime: 1100,
    tracks: .init(screen: .init(firstSampleHostTime: 1000.0625), mic: .init(firstSampleHostTime: 1000.125)),
    pauses: [.init(hostStart: 1030, hostEnd: 1034), .init(hostStart: 1050, hostEnd: 1052)]
)

@Suite("RecordingMeta")
struct RecordingMetaTests {
    @Test("Source time counts from the start of recording")
    func countsFromStart() {
        #expect(meta.sourceTime(hostTime: 1000) == 0)
        #expect(meta.sourceTime(hostTime: 1012.5) == 12.5)
    }

    @Test("Paused time is removed, so source time stays continuous")
    func removesPausedTime() {
        #expect(meta.sourceTime(hostTime: 1040) == 36)  // 40 s in, minus the 4 s pause
        #expect(meta.sourceTime(hostTime: 1060) == 54)  // minus both pauses: 4 s + 2 s
    }

    @Test("Source time stands still during a pause")
    func standsStillDuringPause() {
        #expect(meta.sourceTime(hostTime: 1030) == 30)
        #expect(meta.sourceTime(hostTime: 1032) == 30)
        #expect(meta.sourceTime(hostTime: 1034) == 30)
    }

    @Test("Each track starts at its first sample's source time")
    func trackStartTimes() {
        #expect(meta.startTime(of: \.screen) == 0.0625)
        #expect(meta.startTime(of: \.mic) == 0.125)
        #expect(meta.startTime(of: \.camera) == nil)
    }

    @Test("Pauses appear where they happened in source time")
    func pausePositions() {
        #expect(meta.pausePositions == [30, 46])
    }

    @Test("Duration excludes paused time, and is unknown if recording never stopped")
    func duration() {
        #expect(meta.duration == 94)
        var crashed = meta
        crashed.stopHostTime = nil
        #expect(crashed.duration == nil)
    }

    @Test("Source time never runs backward or faster than the host clock", arguments: 1...50)
    func sourceTimeIsMonotonicAndNeverFaster(seed: UInt64) {
        var random = SeededGenerator(seed: seed)
        let recording = randomMeta(using: &random)
        let hostTimes = (0..<200).map { _ in Double.random(in: 990...1200, using: &random) }.sorted()

        for (earlier, later) in zip(hostTimes, hostTimes.dropFirst()) {
            let step = recording.sourceTime(hostTime: later) - recording.sourceTime(hostTime: earlier)
            // Not exactly 0: inside a pause, floating-point rounding can wobble by ~1e-13.
            #expect(step >= -1e-9, "seed \(seed): went backward between \(earlier) and \(later)")
            #expect(step <= later - earlier + 1e-9, "seed \(seed): ran faster between \(earlier) and \(later)")
        }
    }

    @Test("Total source time is recording time minus all pauses", arguments: 1...50)
    func totalExcludesPauses(seed: UInt64) throws {
        var random = SeededGenerator(seed: seed)
        let recording = randomMeta(using: &random)
        let stop = try #require(recording.stopHostTime)
        let paused = recording.pauses.reduce(0) { $0 + ($1.hostEnd - $1.hostStart) }
        #expect(abs(recording.sourceTime(hostTime: stop) - (stop - recording.startHostTime - paused)) < 1e-9)
    }

    @Test("Saves to the bundle and loads back unchanged")
    func roundTripsThroughBundle() throws {
        try withBundle { bundle in
            try bundle.saveMeta(meta)
            #expect(try bundle.loadMeta() == meta)
        }
    }

    @Test("Writes meta.json in the documented format")
    func writesTheExactFormat() throws {
        try withBundle { bundle in
            var oneTrack = meta
            oneTrack.tracks = .init(screen: .init(firstSampleHostTime: 1000.0625))
            oneTrack.pauses = [.init(hostStart: 1030.25, hostEnd: 1034.5)]
            try bundle.saveMeta(oneTrack)

            #expect(
                try String(contentsOf: bundle.url(for: .meta), encoding: .utf8) == """
                    {
                      "appVersion" : "0.1.0",
                      "capture" : {
                        "displayID" : 1,
                        "displayName" : "Built-in Retina Display",
                        "kind" : "display",
                        "rect" : {
                          "h" : 982,
                          "w" : 1512,
                          "x" : 0,
                          "y" : 0
                        },
                        "scale" : 2
                      },
                      "pauses" : [
                        {
                          "hostEnd" : 1034.5,
                          "hostStart" : 1030.25
                        }
                      ],
                      "schemaVersion" : 1,
                      "startHostTime" : 1000,
                      "stopHostTime" : 1100,
                      "tracks" : {
                        "screen" : {
                          "firstSampleHostTime" : 1000.0625
                        }
                      }
                    }
                    """
            )
        }
    }

    @Test("Refuses meta.json from a newer version")
    func refusesNewerSchemaVersion() throws {
        try withBundle { bundle in
            try Data(#"{"schemaVersion":2}"#.utf8).write(to: bundle.url(for: .meta))
            #expect(throws: ProjectBundle.OpenError.unsupportedSchemaVersion(2)) {
                try bundle.loadMeta()
            }
        }
    }
}

/// A recording of 60–120 s starting at host time 1000, with up to five pauses that
/// don't overlap.
private func randomMeta(using random: inout SeededGenerator) -> RecordingMeta {
    let start = 1000.0
    let stop = start + Double.random(in: 60...120, using: &random)
    var edges = (0..<(2 * Int.random(in: 0...5, using: &random))).map { _ in
        Double.random(in: start...stop, using: &random)
    }
    edges.sort()
    let pauses = stride(from: 0, to: edges.count, by: 2).map {
        RecordingMeta.Pause(hostStart: edges[$0], hostEnd: edges[$0 + 1])
    }
    var recording = meta
    recording.startHostTime = start
    recording.stopHostTime = stop
    recording.pauses = pauses
    return recording
}

/// Runs `body` with a new bundle in a temporary folder that's deleted afterwards.
private func withBundle(_ body: (ProjectBundle) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "RecordingMetaTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(ProjectBundle.create(at: folder.appending(path: "Demo.shipcam"), project: Project(name: "Demo")))
}
