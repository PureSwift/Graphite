import Testing
import GraphiteBase
import GraphiteQuickDraw

@Suite struct CursorStateTests {

    @Test func startsAsTheShownArrow() {
        let state = CursorState()
        #expect(state.current == .arrow)
        #expect(state.isVisible)
    }

    @Test func hidingNests() {
        var state = CursorState()
        state.hide()
        state.hide()
        state.show()
        #expect(!state.isVisible)
        state.show()
        #expect(state.isVisible)
    }

    @Test func showingMoreThanHidingChangesNothing() {
        var state = CursorState()
        state.show()
        state.hide()
        #expect(!state.isVisible)
        state.show()
        #expect(state.isVisible)
    }

    @Test func initializingRestoresTheArrowAndShows() {
        var state = CursorState()
        state.set(Cursor(data: [0xFFFF], mask: [0xFFFF], hotSpot: Point(v: 8, h: 8)))
        state.hide()
        state.hide()
        state.initialize()
        #expect(state.current == .arrow)
        #expect(state.isVisible)
    }

    private func pixels(width: Int, height: Int, value: UInt32) -> PixelBuffer {
        let buffer = PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: Int16(height), right: Int16(width)), format: .argb32)
        buffer.fill(buffer.bounds, with: value)
        return buffer
    }

    @Test func namedCursorsAreSetByName() throws {
        var state = CursorState()
        let buffer = pixels(width: 24, height: 20, value: 0xFF12_3456)
        try state.register(pixels: buffer, hotSpot: Point(v: 3, h: 4), name: "target")
        try state.setNamed("target")
        #expect(state.current.hotSpot == Point(v: 3, h: 4))
        #expect(state.current.colorWidth == 24)
        #expect(state.current.colorImage?.count == 24 * 20)
        #expect(state.current.colorImage?.first == 0xFF12_3456)
    }

    @Test func registeringCopiesThePixels() throws {
        var state = CursorState()
        let buffer = pixels(width: 16, height: 16, value: 0xFF00_00FF)
        try state.register(pixels: buffer, hotSpot: .zero, name: "blue")
        buffer.fill(buffer.bounds, with: 0xFFFF_0000)
        try state.setNamed("blue")
        #expect(state.current.colorImage?.first == 0xFF00_00FF)
    }

    @Test func registeringAgainReplaces() throws {
        var state = CursorState()
        try state.register(pixels: pixels(width: 16, height: 16, value: 0xFF00_0001), hotSpot: .zero, name: "x")
        try state.register(pixels: pixels(width: 16, height: 16, value: 0xFF00_0002), hotSpot: .zero, name: "x")
        try state.setNamed("x")
        #expect(state.current.colorImage?.first == 0xFF00_0002)
    }

    @Test func unregisteredAndBadNamesAreParameterErrors() throws {
        var state = CursorState()
        #expect(throws: MacError.parameter) { try state.setNamed("missing") }
        #expect(throws: MacError.parameter) { try state.unregister("missing") }
        #expect(throws: MacError.parameter) {
            try state.register(pixels: pixels(width: 16, height: 16, value: 0), hotSpot: .zero, name: "")
        }
        let indexed = PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: 16, right: 16), format: .indexed(depth: 8))
        #expect(throws: MacError.parameter) { try state.register(pixels: indexed, hotSpot: .zero, name: "indexed") }

        try state.register(pixels: pixels(width: 16, height: 16, value: 0), hotSpot: .zero, name: "gone")
        try state.unregister("gone")
        #expect(throws: MacError.parameter) { try state.setNamed("gone") }
    }

    @Test func quickDrawKeepsTheState() {
        let quickDraw = QuickDraw(screens: [])
        quickDraw.cursor.hide()
        #expect(!quickDraw.cursor.isVisible)
    }
}
