import Testing
import GraphiteBase
import GraphiteQuickDraw

@Suite struct DrawingTests {

    let red = RGBColor(red8: 0xFF, green8: 0, blue8: 0)
    let blue = RGBColor(red8: 0, green8: 0, blue8: 0xFF)

    private func colorPort(depth: Int = 32) throws -> Port {
        let world = try GraphicsWorld(bounds: Rect(top: 0, left: 0, bottom: 8, right: 8), depth: depth)
        world.port.eraseAll()
        return world.port
    }

    @Test(arguments: [8, 16, 32])
    func paintsInTheForegroundColor(depth: Int) throws {
        let port = try colorPort(depth: depth)
        #expect(port.pixels?.color(at: Point(v: 3, h: 3)) == .white)
        port.foreColor = red
        port.perform(.paint, rect: Rect(top: 2, left: 2, bottom: 4, right: 4))
        #expect(port.pixels?.color(at: Point(v: 3, h: 3)) == red)
        #expect(port.pixels?.color(at: Point(v: 4, h: 4)) == .white)
    }

    @Test func eraseUsesTheBackgroundColor() throws {
        let port = try colorPort()
        port.backColor = blue
        port.perform(.erase, oval: Rect(top: 0, left: 0, bottom: 8, right: 8))
        #expect(port.pixels?.color(at: Point(v: 4, h: 4)) == blue)
        #expect(port.pixels?.color(at: Point(v: 0, h: 0)) == .white)
    }

    @Test func invertingTwiceRestores() throws {
        for depth in [1, 8, 32] {
            let port = try colorPort(depth: depth)
            port.foreColor = red
            port.perform(.paint, rect: Rect(top: 0, left: 0, bottom: 4, right: 8))
            let before = port.pixels.map(snapshot)
            port.perform(.invert, rect: Rect(top: 2, left: 2, bottom: 6, right: 6))
            #expect(port.pixels.map(snapshot) != before)
            port.perform(.invert, rect: Rect(top: 2, left: 2, bottom: 6, right: 6))
            #expect(port.pixels.map(snapshot) == before)
        }
    }

    @Test func drawingIsClipped() throws {
        let port = try colorPort()
        port.foreColor = red
        port.clip(to: Rect(top: 0, left: 0, bottom: 8, right: 4))
        port.perform(.paint, rect: Rect(top: 0, left: 0, bottom: 8, right: 8))
        #expect(port.pixels?.color(at: Point(v: 1, h: 3)) == red)
        #expect(port.pixels?.color(at: Point(v: 1, h: 4)) == .white)
        // The visible region too.
        port.clip(to: port.portRect)
        port.visibleRegion = Region(rect: Rect(top: 0, left: 0, bottom: 2, right: 8))
        port.foreColor = blue
        port.perform(.paint, rect: Rect(top: 0, left: 0, bottom: 8, right: 8))
        #expect(port.pixels?.color(at: Point(v: 1, h: 6)) == blue)
        #expect(port.pixels?.color(at: Point(v: 3, h: 6)) == .white)
    }

    @Test func aHiddenPenDrawsNothing() throws {
        let port = try colorPort()
        port.hidePen()
        port.perform(.paint, rect: Rect(top: 0, left: 0, bottom: 8, right: 8))
        port.move(to: .zero)
        port.line(to: Point(v: 7, h: 7))
        #expect(port.pixels.map(snapshot) == bitmapSnapshotOfWhite(8, 8))
        #expect(port.pen.location == Point(v: 7, h: 7))
        // Erasing and filling aren't the pen's.
        port.perform(.fill(.black), rect: Rect(top: 0, left: 0, bottom: 1, right: 1))
        #expect(port.pixels?.color(at: .zero) == .black)
    }

    @Test func patternModes() throws {
        let port = try colorPort()
        port.pen.mode = .patOr
        port.pen.pattern = .gray
        port.perform(.paint, rect: Rect(top: 0, left: 0, bottom: 2, right: 2))
        #expect(port.pixels?.color(at: Point(v: 0, h: 0)) == .black)
        // patOr leaves what the pattern's clear bits fall on.
        #expect(port.pixels?.color(at: Point(v: 0, h: 1)) == .white)
        // The pattern is the port's, from its pixels' origin.
        port.setOrigin(h: 1, v: 0)
        port.pen.mode = .patCopy
        port.perform(.paint, rect: Rect(top: 4, left: 1, bottom: 5, right: 3))
        #expect(port.pixels?.color(at: Point(v: 4, h: 1)) == .black)
    }

    @Test func frameRegion() throws {
        let port = bitmapPort(width: 6, height: 6)
        port.perform(.frame, region: Region(rect: Rect(top: 1, left: 1, bottom: 5, right: 5)))
        #expect(snapshot(port) == """
        ......
        .####.
        .#..#.
        .#..#.
        .####.
        ......
        """)
    }

    private func bitmapSnapshotOfWhite(_ width: Int, _ height: Int) -> String {
        Array(repeating: String(repeating: ".", count: width), count: height).joined(separator: "\n")
    }
}
