import Testing
import GraphiteBase
import GraphiteQuickDraw

@Suite struct PortTests {

    @Test func worlds() throws {
        let world = try GraphicsWorld(bounds: Rect(top: 0, left: 0, bottom: 20, right: 40), depth: 8)
        #expect(world.pixels.format == .indexed(depth: 8))
        #expect(world.port.portRect == Rect(top: 0, left: 0, bottom: 20, right: 40))
        #expect(world.port.device === world.device)
        #expect(world.device.depth == 8)
        #expect(throws: MacError.parameter) { try GraphicsWorld(bounds: Rect(top: 0, left: 0, bottom: 1, right: 1), depth: 3) }
        #expect(throws: MacError.parameter) { try GraphicsWorld(bounds: .zero, depth: 32) }
        let screen = GraphicsDevice.screen(width: 640, height: 480, depth: 16)
        #expect(try GraphicsWorld(bounds: Rect(top: 0, left: 0, bottom: 2, right: 2), depth: 0, device: screen).pixels.format == .rgb555)
    }

    @Test func setOrigin() throws {
        let world = try GraphicsWorld(bounds: Rect(top: 0, left: 0, bottom: 20, right: 40), depth: 32)
        let port = world.port
        port.clip(to: Rect(top: 0, left: 0, bottom: 5, right: 5))
        port.setOrigin(h: 100, v: 50)
        #expect(port.portRect == Rect(top: 50, left: 100, bottom: 70, right: 140))
        #expect(port.pixelBounds == port.portRect)
        #expect(port.visibleRegion.bounds == port.portRect)
        // The clip region stays where it was.
        #expect(port.clipRegion.bounds == Rect(top: 0, left: 0, bottom: 5, right: 5))
        #expect(port.localToGlobal(Point(v: 50, h: 100)) == .zero)
        #expect(port.globalToLocal(.zero) == Point(v: 50, h: 100))
        // The pixel at the new origin is the first one.
        world.pixels.setValue(7, at: Point(v: 50, h: 100))
        #expect(world.pixels.value(column: 0, row: 0) == 7)
    }

    @Test func drawableRegion() throws {
        let port = Port(pixels: PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: 10, right: 10), format: .argb32))
        port.clip(to: Rect(top: 5, left: -5, bottom: 20, right: 5))
        #expect(port.drawableRegion == Region(rect: Rect(top: 5, left: 0, bottom: 10, right: 5)))
    }

    @Test func pen() {
        let port = Port(portRect: Rect(top: 0, left: 0, bottom: 10, right: 10))
        port.move(to: Point(v: 2, h: 3))
        port.move(dh: 1, dv: 1)
        #expect(port.pen.location == Point(v: 3, h: 4))
        port.hidePen()
        #expect(!port.isPenVisible)
        port.showPen()
        #expect(port.isPenVisible)
        port.pen.size = Point(v: 4, h: 4)
        port.pen.normalize()
        #expect(port.pen.size == Point(v: 1, h: 1))
        #expect(port.pen.location == Point(v: 3, h: 4))
    }

    @Test func patterns() {
        #expect(Pattern.gray.isSet(at: Point(v: 0, h: 0)))
        #expect(!Pattern.gray.isSet(at: Point(v: 0, h: 1)))
        #expect(Pattern.gray.isSet(at: Point(v: 1, h: 1)))
        // It repeats every eight pixels, below zero too.
        #expect(Pattern.gray.isSet(at: Point(v: -8, h: 8)) == Pattern.gray.isSet(at: Point(v: 0, h: 0)))
        #expect(Pattern.black.isSolid && Pattern.white.isSolid && !Pattern.gray.isSolid)
    }

    @Test func transferModes() {
        let red = RGBColor(red8: 0xFF, green8: 0, blue8: 0), blue = RGBColor(red8: 0, green8: 0, blue8: 0xFF)
        func combine(_ mode: TransferMode, _ isForeground: Bool) -> RGBColor {
            mode.combine(isForeground: isForeground, drawn: red, existing: blue, fore: red, back: .white)
        }
        #expect(combine(.srcCopy, true) == red)
        #expect(combine(.srcCopy, false) == .white)
        #expect(combine(.srcOr, false) == blue)
        #expect(combine(.notSrcCopy, false) == red)
        #expect(combine(.srcBic, true) == .white)
        #expect(combine(.patXor, true) == RGBColor(red: 0xFFFF, green: 0xFFFF, blue: 0x0000))
        #expect(combine(.addMax, true) == RGBColor(red: 0xFFFF, green: 0, blue: 0xFFFF))
        #expect(TransferMode(rawValue: 64 | 1).base == .srcOr)
        #expect(TransferMode.transparent.combine(isForeground: true, drawn: .white, existing: blue, fore: .black, back: .white) == blue)
    }

    @Test func quickDrawState() throws {
        let main = GraphicsDevice.screen(width: 640, height: 480)
        let second = GraphicsDevice.screen(width: 800, height: 600)
        second.bounds = Rect(top: 0, left: 640, bottom: 600, right: 1440)
        let quickDraw = QuickDraw(screens: [main, second])
        #expect(quickDraw.mainDevice === main)
        #expect(quickDraw.device(for: Rect(top: 0, left: 600, bottom: 100, right: 900)) === second)
        let world = try GraphicsWorld(bounds: Rect(top: 0, left: 0, bottom: 4, right: 4), depth: 32)
        quickDraw.setWorld(world)
        #expect(quickDraw.currentPort === world.port)
        #expect(quickDraw.currentDevice === world.device)
        #expect(RGBColor(classic: 33) == .black)
        #expect(RGBColor(classic: 1) == nil)
    }
}
