import AppKit
import ProjectModel
import RecorderCore
import SwiftUI

/// A temporary screen for trying the recorder. The recording HUD will replace it.
struct DebugRecorderView: View {
    @State private var recorder: ScreenRecorder?
    @State private var bundle: ProjectBundle?
    @State private var isBusy = false
    @State private var status = "Records the main display into ~/Movies/Shipcam."

    var body: some View {
        VStack(spacing: 20) {
            Text("Debug recorder")
                .font(.title2.bold())
            Button(recorder == nil ? "Record main display" : "Stop") {
                Task { await toggle() }
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(isBusy)
            Text(status)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: 560)
        }
        .padding(32)
        .frame(minWidth: 800, minHeight: 500)
    }

    private func toggle() async {
        isBusy = true
        defer { isBusy = false }
        if let recorder, let bundle {
            await stop(recorder, bundle: bundle)
        } else {
            await start()
        }
    }

    private func start() async {
        guard ScreenRecordingPermission.isGranted || ScreenRecordingPermission.request() else {
            status = """
                Shipcam needs the Screen Recording permission. Turn it on in System Settings → \
                Privacy & Security → Screen & System Audio Recording, then quit and reopen Shipcam.
                """
            return
        }
        do {
            let bundle = try ProjectBundle.create(at: Self.newRecordingURL(), project: Project(name: "Recording"))
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
            recorder = try await ScreenRecorder.recordMainDisplay(into: bundle, appVersion: version)
            self.bundle = bundle
            status = "Recording into \(bundle.url.path)"
        } catch {
            status = "Couldn't start: \(error.localizedDescription)"
        }
    }

    private func stop(_ recorder: ScreenRecorder, bundle: ProjectBundle) async {
        do {
            let summary = try await recorder.stop()
            let total = summary.framesWritten + summary.framesDropped
            let dropRate = total == 0 ? 0 : Double(summary.framesDropped) / Double(total) * 100
            let screenStart = summary.meta.startTime(of: \.screen) ?? .nan
            status = """
                Saved \(String(format: "%.1f", summary.meta.duration ?? 0)) s
                Frames written: \(summary.framesWritten), dropped: \(summary.framesDropped) \
                (\(String(format: "%.2f", dropRate))%)
                Screen track starts \(String(format: "%.3f", screenStart)) s after record was pressed
                \(summary.interruption.map { "Capture stopped early: \($0)" } ?? "")
                """
            NSWorkspace.shared.activateFileViewerSelecting([bundle.url(for: .screen)])
        } catch {
            status = "Couldn't finish the recording: \(error.localizedDescription)"
        }
        self.recorder = nil
        self.bundle = nil
    }

    /// ~/Movies/Shipcam/Recording 2026-10-25 at 14.03.12.shipcam
    private static func newRecordingURL() throws -> URL {
        let folder = URL.moviesDirectory.appending(path: "Shipcam")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return folder.appending(path: "Recording \(formatter.string(from: .now)).shipcam")
    }
}
