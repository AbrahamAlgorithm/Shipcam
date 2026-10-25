import AVFoundation
import CoreMedia
import Foundation
import Testing

@testable import RecorderCore

@Suite("ScreenVideoWriter")
struct ScreenVideoWriterTests {
    @Test("Writes HEVC, with file time 0 at the first frame")
    func writesHEVCFromFirstFrame() async throws {
        try await withTemporaryFile { url in
            let writer = try ScreenVideoWriter(url: url, width: 320, height: 240)
            for hostSeconds in [100.0, 100.5, 101.25] {
                #expect(try writer.append(sampleBuffer(at: hostSeconds)))
            }
            #expect(writer.firstFrameTime?.seconds == 100)
            try await writer.finish(at: nil)

            let movie = try await readMovie(at: url)
            #expect(movie.codec == "hvc1")
            #expect(movie.frameTimes == [0, 0.5, 1.25])
        }
    }

    @Test("Keeps one sample per frame: variable frame rate, nothing duplicated to fill gaps")
    func keepsVariableFrameRate() async throws {
        try await withTemporaryFile { url in
            let writer = try ScreenVideoWriter(url: url, width: 320, height: 240)
            // A busy moment, then the screen sits still for 4 s, then changes once more.
            for hostSeconds in [10.0, 10.0167, 10.0333, 14.0333] {
                try writer.append(sampleBuffer(at: hostSeconds))
            }
            try await writer.finish(at: nil)
            #expect(try await readMovie(at: url).frameTimes.count == 4)
        }
    }

    @Test("Extends the file to the stop time, holding the last frame")
    func extendsToStopTime() async throws {
        try await withTemporaryFile { url in
            let writer = try ScreenVideoWriter(url: url, width: 320, height: 240)
            try writer.append(sampleBuffer(at: 100))
            try writer.append(sampleBuffer(at: 101))
            try await writer.finish(at: hostTime(103))
            #expect(try await readMovie(at: url).duration == 3)
        }
    }

    @Test("Refuses to overwrite an existing file")
    func refusesToOverwrite() async throws {
        try await withTemporaryFile { url in
            try Data("keep me".utf8).write(to: url)
            #expect(throws: (any Error).self) {
                try ScreenVideoWriter(url: url, width: 320, height: 240)
            }
            #expect(try Data(contentsOf: url) == Data("keep me".utf8))
        }
    }

    @Test("A recording with no frames fails and leaves no file")
    func noFrames() async throws {
        try await withTemporaryFile { url in
            let writer = try ScreenVideoWriter(url: url, width: 320, height: 240)
            await #expect(throws: ScreenVideoWriter.WriteError.noFrames) {
                try await writer.finish(at: nil)
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }
}

// MARK: - Helpers

/// Host times use nanoseconds, like ScreenCaptureKit's timestamps.
private func hostTime(_ seconds: Double) -> CMTime {
    CMTime(value: CMTimeValue((seconds * 1e9).rounded()), timescale: 1_000_000_000)
}

/// A gray 320×240 frame in the pixel format ScreenCaptureKit is configured to deliver.
private func sampleBuffer(at hostSeconds: Double) throws -> CMSampleBuffer {
    var pixelBuffer: CVPixelBuffer?
    let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
    let status = CVPixelBufferCreate(
        nil, 320, 240, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes, &pixelBuffer)
    let image = try #require(pixelBuffer, "CVPixelBufferCreate failed: \(status)")
    CVPixelBufferLockBaseAddress(image, [])
    for plane in 0..<CVPixelBufferGetPlaneCount(image) {
        let bytes = CVPixelBufferGetBytesPerRowOfPlane(image, plane) * CVPixelBufferGetHeightOfPlane(image, plane)
        memset(CVPixelBufferGetBaseAddressOfPlane(image, plane), 128, bytes)
    }
    CVPixelBufferUnlockBaseAddress(image, [])
    return try CMSampleBuffer(
        imageBuffer: image,
        formatDescription: CMVideoFormatDescription(imageBuffer: image),
        sampleTiming: CMSampleTimingInfo(
            duration: .invalid, presentationTimeStamp: hostTime(hostSeconds), decodeTimeStamp: .invalid))
}

private struct Movie {
    var codec: String
    var frameTimes: [Double]
    var duration: Double
}

/// Reads back the codec, each frame's time (rounded to the millisecond) and the duration.
private func readMovie(at url: URL) async throws -> Movie {
    let asset = AVURLAsset(url: url)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let format = try #require(try await track.load(.formatDescriptions).first)
    let codec = format.mediaSubType.description.trimmingCharacters(in: CharacterSet(charactersIn: "'"))

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    reader.startReading()
    var frameTimes: [Double] = []
    while let sample = output.copyNextSampleBuffer() {
        if sample.numSamples > 0 {
            frameTimes.append((sample.presentationTimeStamp.seconds * 1000).rounded() / 1000)
        }
    }
    let duration = try await asset.load(.duration).seconds
    return Movie(codec: codec, frameTimes: frameTimes, duration: (duration * 1000).rounded() / 1000)
}

/// Runs `body` with the URL of a file that doesn't exist yet, and deletes it afterwards.
private func withTemporaryFile(_ body: (URL) async throws -> Void) async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "screen-\(UUID().uuidString).mov")
    defer { try? FileManager.default.removeItem(at: url) }
    try await body(url)
}
