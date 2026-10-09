/// One line of `raw/cursor.jsonl` after the header: something the cursor, mouse,
/// keyboard or camera bubble did during the recording.
///
/// `t` is source time: seconds since the recording started. Positions are
/// normalized: 0–1 across the captured source, with (0, 0) at its top-left corner
/// and y growing downward, the same way video frames are laid out.
public struct TelemetryEvent: Equatable, Sendable {
    public var t: Double
    public var kind: Kind

    public init(t: Double, kind: Kind) {
        self.t = t
        self.kind = kind
    }

    public enum Kind: Equatable, Sendable {
        case move(Move)
        case down(ButtonPress)
        case up(ButtonPress)
        case scroll(Scroll)
        case key(Key)
        case caret(Caret)
        case cursorImage(CursorImage)
        case bubble(Bubble)
    }
}

extension TelemetryEvent {
    /// The cursor's position, sampled at the header's `sampleHz`.
    public struct Move: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        /// False while the cursor is outside the captured source.
        public var visible: Bool
        /// The system cursor's shape: a known name such as `arrow` or `iBeam`, or the
        /// `id` of a `cursorImage` event.
        public var cursor: String

        public init(x: Double, y: Double, visible: Bool, cursor: String) {
            self.x = x
            self.y = y
            self.visible = visible
            self.cursor = cursor
        }
    }

    /// A mouse button going down or coming up.
    public struct ButtonPress: Codable, Equatable, Sendable {
        public var button: MouseButton
        public var x: Double
        public var y: Double

        public init(button: MouseButton, x: Double, y: Double) {
            self.button = button
            self.x = x
            self.y = y
        }
    }

    public enum MouseButton: String, Codable, Sendable {
        case left, right, other
    }

    /// A scroll-wheel or trackpad scroll. `dx` and `dy` are the distances macOS reports.
    public struct Scroll: Codable, Equatable, Sendable {
        public var dx: Double
        public var dy: Double
        public var x: Double
        public var y: Double

        public init(dx: Double, dy: Double, x: Double, y: Double) {
            self.dx = dx
            self.dy = dy
            self.x = x
            self.y = y
        }
    }

    /// A key going down or coming up. For privacy, only the kind of key is stored,
    /// unless character logging was turned on for this recording.
    public struct Key: Codable, Equatable, Sendable {
        public var phase: Phase
        public var `class`: KeyClass
        public var mods: [Modifier]
        /// The typed characters, present only when character logging was on.
        public var chars: String?

        public init(phase: Phase, class: KeyClass, mods: [Modifier], chars: String?) {
            self.phase = phase
            self.class = `class`
            self.mods = mods
            self.chars = chars
        }

        public enum Phase: String, Codable, Sendable {
            case down, up
        }
    }

    public enum KeyClass: String, Codable, Sendable {
        case char, enter, delete, combo, other
    }

    public enum Modifier: String, Codable, Sendable {
        case cmd, shift, opt, ctrl, fn
    }

    /// The text caret's bounds in the focused app, read through Accessibility while
    /// typing. Typing zooms aim at it.
    public struct Caret: Codable, Equatable, Sendable {
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

    /// A cursor image Shipcam didn't recognize, saved once under `cache/cursors/`.
    public struct CursorImage: Codable, Equatable, Sendable {
        public var id: String
        /// The click point within the image, 0–1. Stored as `[x, y]`.
        public var hotspot: SIMD2<Double>

        public init(id: String, hotspot: SIMD2<Double>) {
            self.id = id
            self.hotspot = hotspot
        }
    }

    /// Where the floating camera bubble was, so the editor can put the webcam there.
    /// `x` and `y` are 0–1 of the captured display.
    public struct Bubble: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var size: Size
        public var shape: Shape
        public var visible: Bool

        public init(x: Double, y: Double, size: Size, shape: Shape, visible: Bool) {
            self.x = x
            self.y = y
            self.size = size
            self.shape = shape
            self.visible = visible
        }

        public enum Size: String, Codable, Sendable {
            case small, medium, large
        }

        public enum Shape: String, Codable, Sendable {
            case circle, roundedRect, square
        }
    }
}

extension TelemetryEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case t, type
    }

    /// Thrown for a `type` this version doesn't know, such as one added by a newer Shipcam.
    struct UnknownType: Error {
        let type: String
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        t = try container.decode(Double.self, forKey: .t)
        // Each payload reads its own keys from the same JSON object.
        switch try container.decode(String.self, forKey: .type) {
        case "move": kind = .move(try Move(from: decoder))
        case "down": kind = .down(try ButtonPress(from: decoder))
        case "up": kind = .up(try ButtonPress(from: decoder))
        case "scroll": kind = .scroll(try Scroll(from: decoder))
        case "key": kind = .key(try Key(from: decoder))
        case "caret": kind = .caret(try Caret(from: decoder))
        case "cursorImage": kind = .cursorImage(try CursorImage(from: decoder))
        case "bubble": kind = .bubble(try Bubble(from: decoder))
        case let type: throw UnknownType(type: type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        let (type, payload): (String, any Encodable) =
            switch kind {
            case .move(let move): ("move", move)
            case .down(let press): ("down", press)
            case .up(let press): ("up", press)
            case .scroll(let scroll): ("scroll", scroll)
            case .key(let key): ("key", key)
            case .caret(let caret): ("caret", caret)
            case .cursorImage(let image): ("cursorImage", image)
            case .bubble(let bubble): ("bubble", bubble)
            }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(t, forKey: .t)
        try container.encode(type, forKey: .type)
        try payload.encode(to: encoder)
    }
}
