/// A rectangle with (0, 0) at the top-left and y growing downward. Its unit depends
/// on where it's used: points for a capture area, 0–1 for normalized positions.
public struct Rect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}
