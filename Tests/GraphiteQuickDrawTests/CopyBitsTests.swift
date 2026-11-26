import Testing
import GraphiteBase
import GraphiteQuickDraw

@Suite struct CopyBitsTests {

    let red = RGBColor(red8: 0xFF, green8: 0, blue8: 0)
    let blue = RGBColor(red8: 0, green8: 0, blue8: 0xFF)

    private func world(_ width: Int16, _ height: Int16, depth: Int) throws -> GraphicsWorld {
        let world = try GraphicsWorld(bounds: Rect(top: 0, left: 0, bottom: height, right: width), depth: depth)
        world.port.eraseAll()
        return world
    }

    @Test func copiesBetweenDepths() throws {
        let source = try world(4, 4, depth: 8)
        source.port.foreColor = red
        source.port.perform(.paint, rect: Rect(top: 0, left: 0, bottom: 2, right: 2))
        for depth in [16, 32, 8] {
            let destination = try world(4, 4, depth: depth)
            destination.port.copyBits(from: source.pixels, sourceRect: source.port.portRect, destinationRect: destination.port.portRect)
            #expect(destination.pixels.color(at: Point(v: 1, h: 1)) == red)
            #expect(destination.pixels.color(at: Point(v: 3, h: 3)) == .white)
        }
    }

    @Test func bitmapsAreColorized() throws {
        let bitmap = bitmapPort(width: 2, height: 1)
        bitmap.perform(.paint, rect: Rect(top: 0, left: 0, bottom: 1, right: 1))
        let destination = try world(2, 1, depth: 32)
        destination.port.foreColor = red
        destination.port.backColor = blue
        destination.port.copyBits(from: bitmap.pixels!, sourceRect: bitmap.portRect, destinationRect: destination.port.portRect)
        #expect(destination.pixels.color(at: Point(v: 0, h: 0)) == red)
        #expect(destination.pixels.color(at: Point(v: 0, h: 1)) == blue)
        // srcOr leaves what the clear bits fall on: here, the background
        // the port was erased to.
        destination.port.eraseAll()
        destination.port.foreColor = .black
        destination.port.copyBits(from: bitmap.pixels!, sourceRect: bitmap.portRect, destinationRect: destination.port.portRect, mode: .srcOr)
        #expect(destination.pixels.color(at: Point(v: 0, h: 0)) == .black)
        #expect(destination.pixels.color(at: Point(v: 0, h: 1)) == blue)
    }

    @Test func scaling() throws {
        let source = bitmapPort(width: 2, height: 2)
        source.perform(.paint, rect: Rect(top: 0, left: 0, bottom: 1, right: 1))
        source.perform(.paint, rect: Rect(top: 1, left: 1, bottom: 2, right: 2))
        let doubled = bitmapPort(width: 4, height: 4)
        doubled.copyBits(from: source.pixels!, sourceRect: source.portRect, destinationRect: doubled.portRect)
        #expect(snapshot(doubled) == """
        ##..
        ##..
        ..##
        ..##
        """)
        let halved = bitmapPort(width: 1, height: 1)
        halved.copyBits(from: doubled.pixels!, sourceRect: doubled.portRect, destinationRect: halved.portRect)
        #expect(snapshot(halved) == "#")
    }

    @Test func maskRegionsAndClipping() throws {
        let source = try world(4, 4, depth: 32)
        source.port.foreColor = red
        source.port.perform(.paint, rect: source.port.portRect)
        let destination = try world(4, 4, depth: 32)
        destination.port.clip(to: Rect(top: 0, left: 0, bottom: 4, right: 3))
        destination.port.copyBits(from: source.pixels, sourceRect: source.port.portRect, destinationRect: destination.port.portRect,
                                  mask: .oval(in: destination.port.portRect))
        #expect(destination.pixels.color(at: Point(v: 1, h: 1)) == red)
        #expect(destination.pixels.color(at: Point(v: 0, h: 0)) == .white)
        #expect(destination.pixels.color(at: Point(v: 1, h: 3)) == .white)
    }

    @Test func transparentAndArithmeticModes() throws {
        let source = try world(2, 1, depth: 32)
        source.pixels.setColor(red, at: Point(v: 0, h: 0))
        let destination = try world(2, 1, depth: 32)
        destination.port.backColor = .white
        destination.port.perform(.erase, rect: destination.port.portRect)
        destination.pixels.setColor(blue, at: Point(v: 0, h: 1))
        destination.port.copyBits(from: source.pixels, sourceRect: source.port.portRect, destinationRect: destination.port.portRect, mode: .transparent)
        #expect(destination.pixels.color(at: Point(v: 0, h: 0)) == red)
        #expect(destination.pixels.color(at: Point(v: 0, h: 1)) == blue)
        destination.port.copyBits(from: source.pixels, sourceRect: source.port.portRect, destinationRect: destination.port.portRect, mode: .addMin)
        #expect(destination.pixels.color(at: Point(v: 0, h: 1)) == blue)
    }

    @Test func copyMask() throws {
        let source = try world(2, 1, depth: 32)
        source.port.foreColor = red
        source.port.perform(.paint, rect: source.port.portRect)
        let mask = bitmapPort(width: 2, height: 1)
        mask.perform(.paint, rect: Rect(top: 0, left: 1, bottom: 1, right: 2))
        let destination = try world(2, 1, depth: 32)
        destination.port.copyMask(from: source.pixels, mask: mask.pixels!, sourceRect: source.port.portRect,
                                  maskRect: mask.portRect, destinationRect: destination.port.portRect)
        #expect(destination.pixels.color(at: Point(v: 0, h: 0)) == .white)
        #expect(destination.pixels.color(at: Point(v: 0, h: 1)) == red)
    }

    @Test func scrollRect() throws {
        let port = bitmapPort(width: 4, height: 3)
        port.perform(.paint, rect: Rect(top: 0, left: 0, bottom: 3, right: 1))
        let update = port.scroll(port.portRect, dh: 2, dv: 0)
        #expect(snapshot(port) == """
        ..#.
        ..#.
        ..#.
        """)
        #expect(update == Region(rect: Rect(top: 0, left: 0, bottom: 3, right: 2)))
        // Up, over itself.
        let column = bitmapPort(width: 1, height: 4)
        column.perform(.paint, rect: Rect(top: 2, left: 0, bottom: 3, right: 1))
        column.scroll(column.portRect, dh: 0, dv: -1)
        #expect(snapshot(column) == """
        .
        #
        .
        .
        """)
    }
}
