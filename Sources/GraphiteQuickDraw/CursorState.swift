// The cursor a program has set: InitCursor, SetCursor, HideCursor and
// ShowCursor, and the cursors it made of its own pixels and set by name.
// A host reads `current` and `isVisible` to show the cursor.

import GraphiteBase

public struct CursorState: Hashable, Sendable {

    /// The cursor to show: the arrow until a program sets another.
    public private(set) var current = Cursor.arrow

    /// HideCursor calls not yet matched by ShowCursor.
    public private(set) var hideCount = 0

    private var named: [String: Cursor] = [:]

    public init() {}

    public var isVisible: Bool { hideCount == 0 }

    /// InitCursor: the arrow, shown.
    public mutating func initialize() {
        current = .arrow
        hideCount = 0
    }

    /// SetCursor.
    public mutating func set(_ cursor: Cursor) {
        current = cursor
    }

    /// HideCursor. Calls nest.
    public mutating func hide() {
        hideCount += 1
    }

    /// ShowCursor. More calls than HideCursor's change nothing.
    public mutating func show() {
        if hideCount > 0 { hideCount -= 1 }
    }

    /// QDRegisterNamedPixMapCursor: a cursor of 32-bit ARGB pixels, kept
    /// under a name; a name used before is replaced. The pixels are copied,
    /// as the program goes on to free its world.
    public mutating func register(pixels: PixelBuffer, hotSpot: Point, name: String) throws(MacError) {
        guard !name.isEmpty, pixels.format == .argb32, pixels.width > 0, pixels.height > 0 else { throw .parameter }
        var image: [UInt32] = []
        image.reserveCapacity(pixels.width * pixels.height)
        for row in 0 ..< pixels.height {
            for column in 0 ..< pixels.width {
                image.append(pixels.value(column: column, row: row))
            }
        }
        named[name] = Cursor(data: [], mask: [], hotSpot: hotSpot, colorImage: image, colorWidth: pixels.width)
    }

    /// QDSetNamedPixMapCursor.
    public mutating func setNamed(_ name: String) throws(MacError) {
        guard let cursor = named[name] else { throw .parameter }
        current = cursor
    }

    /// QDUnregisterNamedPixMapCursor. The cursor on show stays until another is set.
    public mutating func unregister(_ name: String) throws(MacError) {
        guard named.removeValue(forKey: name) != nil else { throw .parameter }
    }
}
