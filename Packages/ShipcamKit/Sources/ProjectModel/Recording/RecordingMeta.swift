/// `raw/meta.json`: the facts needed to line up every track of a recording in time.
///
/// Every source (screen, audio, camera, input events) timestamps its samples on the
/// same host clock, the Mac's monotonic clock that counts from boot, here in seconds.
/// This file stores those raw facts. `sourceTime(hostTime:)` turns any host time into
/// source time, the timeline the rest of Shipcam uses.
///
/// Source time 0 is the moment recording started, which is also the zero for `t` in
/// `cursor.jsonl`. Paused time is left out, so source time has no gaps.
///
/// The recorder rewrites this file as recording goes (start, each track's first
/// sample, each pause, stop), so a crash still leaves enough to sync the tracks. Once
/// recording stops, it never changes.
public struct RecordingMeta: Codable, Equatable, Sendable {
    /// The newest `meta.json` version this code reads and writes.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// The Shipcam version that made the recording, for diagnosing problems.
    public var appVersion: String
    public var capture: Capture
    /// Host time when recording started: source time 0.
    public var startHostTime: Double
    /// Host time when recording stopped, or nil if it never stopped cleanly.
    public var stopHostTime: Double?
    public var tracks: Tracks
    public var pauses: [Pause]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        appVersion: String,
        capture: Capture,
        startHostTime: Double,
        stopHostTime: Double?,
        tracks: Tracks,
        pauses: [Pause]
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.capture = capture
        self.startHostTime = startHostTime
        self.stopHostTime = stopHostTime
        self.tracks = tracks
        self.pauses = pauses
    }

    public struct Capture: Codable, Equatable, Sendable {
        public var kind: CaptureKind
        /// The macOS display ID (`CGDirectDisplayID`).
        public var displayID: UInt32
        public var displayName: String
        /// The captured area within the display, in points.
        public var rect: Rect
        /// Pixels per point: 2 on a Retina display.
        public var scale: Double

        public init(kind: CaptureKind, displayID: UInt32, displayName: String, rect: Rect, scale: Double) {
            self.kind = kind
            self.displayID = displayID
            self.displayName = displayName
            self.rect = rect
            self.scale = scale
        }
    }

    /// The media tracks this recording has. A missing track wasn't recorded.
    public struct Tracks: Codable, Equatable, Sendable {
        public var screen: Track?
        public var system: Track?
        public var mic: Track?
        public var camera: Track?

        public init(screen: Track? = nil, system: Track? = nil, mic: Track? = nil, camera: Track? = nil) {
            self.screen = screen
            self.system = system
            self.mic = mic
            self.camera = camera
        }
    }

    public struct Track: Codable, Equatable, Sendable {
        /// Host time of the track's first sample: where its file's own time 0 falls.
        public var firstSampleHostTime: Double

        public init(firstSampleHostTime: Double) {
            self.firstSampleHostTime = firstSampleHostTime
        }
    }

    /// A span of host time when recording was paused. Nothing was recorded during it.
    public struct Pause: Codable, Equatable, Sendable {
        public var hostStart: Double
        public var hostEnd: Double

        public init(hostStart: Double, hostEnd: Double) {
            self.hostStart = hostStart
            self.hostEnd = hostEnd
        }
    }
}

extension RecordingMeta {
    /// Converts a host time to source time: seconds since recording started, not
    /// counting time spent paused. During a pause, source time stands still.
    public func sourceTime(hostTime: Double) -> Double {
        // Each pause takes away the part of it that lies before `hostTime`: all of it,
        // some of it, or none (max(0, …) covers pauses that haven't started yet).
        let paused = pauses.reduce(0.0) { total, pause in
            total + max(0, min(hostTime, pause.hostEnd) - pause.hostStart)
        }
        return hostTime - startHostTime - paused
    }

    /// When `track` starts in source time, or nil if the recording doesn't have it.
    public func startTime(of track: KeyPath<Tracks, Track?>) -> Double? {
        tracks[keyPath: track].map { sourceTime(hostTime: $0.firstSampleHostTime) }
    }

    /// Where each pause happened in source time, for markers on the timeline.
    public var pausePositions: [Double] {
        pauses.map { sourceTime(hostTime: $0.hostStart) }
    }

    /// The recording's length in source time, or nil if it never stopped cleanly. In
    /// that case the media files' own lengths are the best guide.
    public var duration: Double? {
        stopHostTime.map { sourceTime(hostTime: $0) }
    }
}
