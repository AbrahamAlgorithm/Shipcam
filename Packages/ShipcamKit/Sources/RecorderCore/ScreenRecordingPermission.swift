import CoreGraphics

/// The macOS Screen Recording permission (System Settings → Privacy & Security →
/// Screen & System Audio Recording).
public enum ScreenRecordingPermission {
    /// Whether Shipcam may record the screen. Never shows a prompt.
    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Asks macOS for permission. The first time, macOS shows a prompt; after that, the
    /// user can only change it in System Settings. Returns whether access is granted
    /// now. A newly granted permission may only take effect after the app relaunches.
    @discardableResult
    public static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
