import AVFoundation
import CoreMedia
import Foundation

/// Writes screen frames to `raw/screen.mov`, encoded as HEVC.
///
/// ScreenCaptureKit only delivers a frame when something on screen changes, so the
/// file has a variable frame rate: each frame keeps its own timestamp, and nothing is
/// duplicated to fill gaps. Players, and Shipcam's renderer, hold the last frame.
///
/// File time 0 is the first frame. Frames carry host-clock timestamps; the first one is
/// kept in `firstFrameTime` so `meta.json` can place the file on the recording's
/// timeline.
///
/// The movie is written in fragments every 2 seconds, so if the app crashes, everything
/// up to the last fragment can still be played.
///
/// Not thread-safe: give it a single owner, such as one serial queue.
final class ScreenVideoWriter {
    enum WriteError: Error, Equatable {
        /// The encoder doesn't accept these settings on this Mac.
        case unsupportedSettings
        /// `finish(at:)` was called before any frame was written.
        case noFrames
    }

    /// The host time of the first frame written, which is the file's time 0.
    private(set) var firstFrameTime: CMTime?
    private var lastFrameTime: CMTime?
    private let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput

    /// Creates the file. Throws if one already exists at `url`: raw files are written once.
    init(url: URL, width: Int, height: Int) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path])
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                // About 0.1 bits per pixel per frame at 60 fps, enough for sharp text.
                // Screens are mostly still, so real files come out far smaller.
                AVVideoAverageBitRateKey: Int(Double(width * height) * 60 * 0.1),
                AVVideoExpectedSourceFrameRateKey: 60,
                // This file is edited, not just played. No B-frames means frames are
                // stored in the order they're shown, and a keyframe every second keeps
                // any seek short.
                AVVideoAllowFrameReorderingKey: false,
                AVVideoMaxKeyFrameIntervalDurationKey: 1,
            ],
        ]
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.movieFragmentInterval = CMTime(value: 2, timescale: 1)
        // AVAssetWriterInput raises an Objective-C exception for settings the encoder
        // rejects, and Swift can't catch those, so check first and throw instead.
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw WriteError.unsupportedSettings
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw WriteError.unsupportedSettings }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? WriteError.unsupportedSettings }

        self.url = url
        self.writer = writer
        self.input = input
    }

    /// Appends one frame. Returns false if the encoder was busy and the frame was
    /// dropped, so the caller can count drops.
    @discardableResult
    func append(_ sampleBuffer: CMSampleBuffer) throws -> Bool {
        guard input.isReadyForMoreMediaData else { return false }
        let time = sampleBuffer.presentationTimeStamp
        if firstFrameTime == nil {
            writer.startSession(atSourceTime: time)
            firstFrameTime = time
        }
        guard input.append(sampleBuffer) else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        lastFrameTime = time
        return true
    }

    /// Finishes the file. With an `endTime`, the last frame is held until then, so the
    /// movie lasts until the moment recording stopped. With no frames written, the file
    /// is deleted and `noFrames` is thrown.
    func finish(at endTime: CMTime?) async throws {
        guard let lastFrameTime else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw WriteError.noFrames
        }
        if let endTime, endTime > lastFrameTime {
            writer.endSession(atSourceTime: endTime)
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
    }
}
