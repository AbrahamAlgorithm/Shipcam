/// What was recorded: a whole display, one window, or an area the user dragged out.
public enum CaptureKind: String, Codable, Sendable {
    case display, window, area
}
