import AppKit
import CoreMedia
import Foundation
import ProjectModel
import ScreenCaptureKit
import os

/// Records a display to `raw/screen.mov` and keeps `raw/meta.json` up to date.
///
/// The system cursor is left out of the video, because Shipcam redraws it from
/// telemetry, and Shipcam's own windows are excluded.
///
/// ScreenCaptureKit delivers frames on `queue`, and all mutable state is touched only
/// there, which `dispatchPrecondition` checks at runtime. That rule is what makes
/// `@unchecked Sendable` true. `stop()` takes over the writer only after the queue has
/// been drained and later frames are turned away.
public final class ScreenRecorder: NSObject, @unchecked Sendable {
    public struct Summary: Sendable {
        public var meta: RecordingMeta
        public var framesWritten: Int
        public var framesDropped: Int
        /// Why capture ended early, if it did (for example, the display was disconnected).
        public var interruption: String?
    }

    public enum StartError: Error, Equatable {
        case noDisplay
        /// Less than 2 GB free on the recording's volume.
        case lowDiskSpace(availableBytes: Int64)
    }

    private static let minimumFreeBytes: Int64 = 2_000_000_000
    private static let logger = Logger(subsystem: "com.abrahamfolorunso.shipcam", category: "ScreenRecorder")

    private let queue = DispatchQueue(label: "com.abrahamfolorunso.shipcam.screen-recorder")
    private let bundle: ProjectBundle
    private var stream: SCStream?

    // Touched only on `queue` until `stop()` drains it.
    private let writer: ScreenVideoWriter
    private var meta: RecordingMeta
    private var stopTime: CMTime?
    private var framesWritten = 0
    private var framesDropped = 0
    private var interruption: (any Error)?

    private init(bundle: ProjectBundle, writer: ScreenVideoWriter, meta: RecordingMeta) {
        self.bundle = bundle
        self.writer = writer
        self.meta = meta
    }

    /// Starts recording the main display into `bundle`.
    public static func recordMainDisplay(
        into bundle: ProjectBundle,
        appVersion: String
    ) async throws -> ScreenRecorder {
        try checkDiskSpace(at: bundle.url)

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard
            let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
        else { throw StartError.noDisplay }
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let scale = Double(filter.pointPixelScale)
        let area = filter.contentRect  // in points
        let width = Int((area.width * scale).rounded())
        let height = Int((area.height * scale).rounded())

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.queueDepth = 6

        let meta = RecordingMeta(
            appVersion: appVersion,
            capture: .init(
                kind: .display,
                displayID: display.displayID,
                displayName: await displayName(of: display.displayID),
                rect: Rect(x: area.minX, y: area.minY, w: area.width, h: area.height),
                scale: scale
            ),
            startHostTime: hostTimeNow().seconds,
            stopHostTime: nil,
            tracks: .init(),
            pauses: []
        )
        try bundle.saveMeta(meta)

        let writer = try ScreenVideoWriter(url: bundle.url(for: .screen), width: width, height: height)
        let recorder = ScreenRecorder(bundle: bundle, writer: writer, meta: meta)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: recorder)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: recorder.queue)
        recorder.stream = stream
        try await stream.startCapture()
        return recorder
    }

    /// Stops recording, finishes `screen.mov`, and writes the stop time to `meta.json`
    /// and the duration to `project.json`.
    public func stop() async throws -> Summary {
        let stopTime = Self.hostTimeNow()
        // From here on, frames from after the stop are turned away.
        queue.sync { self.stopTime = stopTime }
        do {
            try await stream?.stopCapture()
        } catch {
            // Already stopped, for example after the display was disconnected.
            Self.logger.notice("stopCapture: \(error.localizedDescription)")
        }
        // Let frames already queued finish. After this, no callback touches the writer,
        // so it's safe to finish it here.
        queue.sync {}
        try await writer.finish(at: stopTime)

        // The other state stays on the queue: the delegate may still report an error.
        let (meta, written, dropped, interruption) = queue.sync {
            self.meta.stopHostTime = stopTime.seconds
            return (self.meta, self.framesWritten, self.framesDropped, self.interruption)
        }
        try bundle.saveMeta(meta)
        var project = try bundle.loadProject()
        project.source.durationSec = meta.duration ?? 0
        try bundle.save(project)

        return Summary(
            meta: meta,
            framesWritten: written,
            framesDropped: dropped,
            interruption: interruption?.localizedDescription
        )
    }

    private static func hostTimeNow() -> CMTime {
        CMClockGetTime(CMClockGetHostTimeClock())
    }

    private static func checkDiskSpace(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available < minimumFreeBytes {
            throw StartError.lowDiskSpace(availableBytes: available)
        }
    }

    @MainActor
    private static func displayName(of displayID: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first { ($0.deviceDescription[key] as? NSNumber)?.uint32Value == displayID }
        return screen?.localizedName ?? "Display \(displayID)"
    }

    /// ScreenCaptureKit also sends updates when nothing changed; only frames whose
    /// status is `complete` carry a new image.
    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: rawStatus)
        else { return false }
        return status == .complete
    }
}

extension ScreenRecorder: SCStreamOutput {
    public func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType
    ) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard type == .screen, sampleBuffer.isValid, Self.isCompleteFrame(sampleBuffer) else { return }
        let time = sampleBuffer.presentationTimeStamp
        if let stopTime, time > stopTime { return }

        do {
            let isFirstFrame = writer.firstFrameTime == nil
            guard try writer.append(sampleBuffer) else {
                framesDropped += 1
                return
            }
            framesWritten += 1
            if isFirstFrame {
                // Saved right away, so even a crash leaves enough to sync this track.
                meta.tracks.screen = .init(firstSampleHostTime: time.seconds)
                try bundle.saveMeta(meta)
            }
        } catch {
            interruption = error
            Self.logger.error("Writing a frame failed: \(error.localizedDescription)")
        }
    }
}

extension ScreenRecorder: SCStreamDelegate {
    /// Called when capture stops on its own, such as when the display is disconnected
    /// or the permission is revoked. `stop()` still finishes the file.
    public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Self.logger.error("Capture stopped: \(error.localizedDescription)")
        queue.async { self.interruption = error }
    }
}
