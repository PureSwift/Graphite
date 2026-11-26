import Testing
import GraphiteBase
import GraphiteQuickDraw
import GraphiteText

@Suite struct LayoutTests {

    let fonts = FontRegistry()
    let red = RGBColor(red8: 0xFF, green8: 0, blue8: 0)

    private func layout(_ text: String, width: Double? = nil, runs: [TextRun]? = nil) -> TextLayout {
        TextLayout(text: text, runs: runs ?? [TextRun(range: 0 ..< text.unicodeScalars.count)], fonts: fonts, width: width)
    }

    @Test func measuresAsQuickDrawDoes() {
        let layout = layout("Hi!")
        let port = Port(portRect: .zero)
        #expect(layout.width == Double(port.textWidth("Hi!".unicodeScalars, fonts: fonts)))
        #expect(layout.lines.count == 1)
        #expect(layout.height == 14)
        #expect(layout.lines[0].baseline == 12)
    }

    @Test func linesBreakAtSpacesAndReturns() {
        let wrapped = layout("ab cd ef", width: 30)
        #expect(wrapped.lines.map(\.range) == [0 ..< 3, 3 ..< 6, 6 ..< 8])
        #expect(wrapped.lines[1].baseline == 12 + 2 + 12)
        let returns = layout("a\rb\nc")
        #expect(returns.lines.count == 3)
        #expect(returns.lines.map(\.range) == [0 ..< 2, 2 ..< 4, 4 ..< 5])
        #expect(layout("").lines.count == 1)
    }

    @Test func positionsAndHitTesting() {
        let layout = layout("Hi")
        // H is 8 pixels with its spacing, i is 4.
        #expect(layout.position(ofOffset: 0).x == 0)
        #expect(layout.position(ofOffset: 1).x == 8)
        #expect(layout.position(ofOffset: 2).x == 12)
        #expect(layout.offset(atX: 1, y: 5) == 0)
        #expect(layout.offset(atX: 6, y: 5) == 1)
        #expect(layout.offset(atX: 9, y: 5) == 1)
        #expect(layout.offset(atX: 100, y: 5) == 2)
        let two = self.layout("ab\ncd")
        #expect(two.offset(atX: 0, y: 20) == 3)
        #expect(two.position(ofOffset: 4).baseline == two.lines[1].baseline)
    }

    @Test func runsHaveTheirOwnSizesAndColors() {
        let runs = [TextRun(range: 0 ..< 1), TextRun(range: 1 ..< 2, size: 24, color: red)]
        let styled = layout("HH", runs: runs)
        #expect(styled.lines[0].characters[1].advance == 2 * styled.lines[0].characters[0].advance)
        #expect(styled.lines[0].ascent == 24)
        let port = Port(pixels: PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: 40, right: 60), format: .argb32))
        port.perform(.erase, rect: port.portRect)
        styled.draw(in: port, at: Point(v: 2, h: 2))
        // The first H small and black, the second large and red.
        #expect(port.pixels?.color(at: Point(v: 2 + 24 - 5, h: 2 + 1)) == .black)
        #expect(port.pixels?.color(at: Point(v: 2 + 24 - 5, h: 2 + 8 + 2)) == red)
        // The port's own settings are back.
        #expect(port.foreColor == .black)
        #expect(port.text.size == 0)
    }

    @Test func pictureText() throws {
        var writer = BigEndianWriter()
        writer.write(UInt16(0))
        for value: Int16 in [0, 0, 16, 40] { writer.write(UInt16(bitPattern: value)) }
        writer.write(bytes: [0x00, 0x11, 0x02, 0xFF, 0x0C, 0x00])
        writer.writeZeros(24)
        writer.write(UInt16(0x0028))                            // LongText
        writer.write(UInt16(12))
        writer.write(UInt16(1))
        writer.write(bytes: ("Hi" as PascalString).lengthPrefixed)
        writer.write(bytes: [0x00])
        writer.write(UInt16(0x00FF))
        let picture = try Picture(bytes: writer.bytes)
        let port = Port(pixels: PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: 16, right: 40), format: .indexed(depth: 1)))
        port.perform(.erase, rect: port.portRect)
        picture.draw(in: port, destination: port.portRect, text: fonts)
        #expect(port.pixels?.color(at: Point(v: 5, h: 1)) == .black)
        let plain = Port(pixels: PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: 16, right: 40), format: .indexed(depth: 1)))
        plain.perform(.erase, rect: plain.portRect)
        picture.draw(in: plain, destination: plain.portRect)
        #expect(plain.pixels?.color(at: Point(v: 5, h: 1)) == .white)
    }
}
