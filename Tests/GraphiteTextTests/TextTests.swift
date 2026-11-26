import Testing
import GraphiteBase
import GraphiteQuickDraw
import GraphiteText

@Suite struct TextTests {

    let fonts = FontRegistry()

    private func port(width: Int16 = 40, height: Int16 = 16, depth: Int = 1) -> Port {
        let format = PixelFormat(depth: depth)!
        let port = Port(pixels: PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: height, right: width), format: format))
        port.perform(.erase, rect: port.portRect)
        return port
    }

    private func snapshot(_ port: Port, rows: Range<Int16>, columns: Range<Int16>) -> String {
        rows.map { v in
            String(columns.map { port.pixels!.color(at: Point(v: v, h: $0)) == .black ? "#" : "." })
        }.joined(separator: "\n")
    }

    @Test func drawString() {
        let port = port()
        port.move(to: Point(v: 12, h: 1))
        port.drawText("Hi!".unicodeScalars, fonts: fonts)
        #expect(snapshot(port, rows: 3 ..< 12, columns: 0 ..< 18) == """
        .##..##..##...##..
        .##..##.......##..
        .##..##..##...##..
        .##..##..##...##..
        .######..##...##..
        .##..##..##...##..
        .##..##..##...##..
        .##..##..##.......
        .##..##..##...##..
        """)
        #expect(port.pen.location == Point(v: 12, h: 18))
        #expect(port.textWidth("Hi!".unicodeScalars, fonts: fonts) == 17)
    }

    @Test func styles() {
        let plain = port().textWidth("Hi!".unicodeScalars, fonts: fonts)
        let bold = port()
        bold.text.face = TextStyle.bold.rawValue
        #expect(bold.textWidth("Hi!".unicodeScalars, fonts: fonts) == plain + 3)
        let condensed = port()
        condensed.text.face = TextStyle.condense.rawValue
        #expect(condensed.textWidth("Hi!".unicodeScalars, fonts: fonts) == plain - 3)
        let underlined = port()
        underlined.text.face = TextStyle.underline.rawValue
        underlined.move(to: Point(v: 12, h: 1))
        underlined.drawText("Hi".unicodeScalars, fonts: fonts)
        #expect(snapshot(underlined, rows: 13 ..< 14, columns: 0 ..< 14) == ".############.")
        let italic = port()
        italic.text.face = TextStyle.italic.rawValue
        italic.move(to: Point(v: 12, h: 1))
        italic.drawText("I".unicodeScalars, fonts: fonts)
        // A pixel to the right every four rows up.
        let top = snapshot(italic, rows: 3 ..< 4, columns: 0 ..< 8), bottom = snapshot(italic, rows: 11 ..< 12, columns: 0 ..< 8)
        #expect(top.firstIndex(of: "#")! > bottom.firstIndex(of: "#")!)
        #expect(italic.fontInfo(fonts: fonts).widMax > port().fontInfo(fonts: fonts).widMax)
    }

    @Test func outline() {
        let port = port()
        port.text.face = TextStyle.outline.rawValue
        port.move(to: Point(v: 12, h: 1))
        port.drawText("H".unicodeScalars, fonts: fonts)
        #expect(snapshot(port, rows: 2 ..< 13, columns: 0 ..< 8) == """
        ########
        #..##..#
        #..##..#
        #..##..#
        #..##..#
        #......#
        #..##..#
        #..##..#
        #..##..#
        #..##..#
        ########
        """)
    }

    @Test func metricsAndSizes() {
        let port = port()
        #expect(port.fontInfo(fonts: fonts) == FontMetrics(ascent: 12, descent: 2, widMax: 12, leading: 0))
        port.text.size = 24
        #expect(port.fontInfo(fonts: fonts).ascent == 24)
        let width12 = self.port().textWidth("abc".unicodeScalars, fonts: fonts)
        #expect(port.textWidth("abc".unicodeScalars, fonts: fonts) == width12 * 2)
    }

    @Test func extras() {
        let plain = port().textWidth("a b".unicodeScalars, fonts: fonts)
        let spaced = port()
        spaced.text.spaceExtra = Fixed(3)
        #expect(spaced.textWidth("a b".unicodeScalars, fonts: fonts) == plain + 3)
        let extra = port()
        extra.text.characterExtra = Fixed(1)
        #expect(extra.textWidth("a b".unicodeScalars, fonts: fonts) == plain + 3)
    }

    @Test func charactersItHasntAreQuestionMarks() {
        #expect(port().textWidth("é".unicodeScalars, fonts: fonts) == port().textWidth("?".unicodeScalars, fonts: fonts))
        // MacRoman bytes, as Pascal strings hold them.
        #expect(port().textWidth(macRoman: ("Hi" as PascalString).bytes, fonts: fonts) == port().textWidth("Hi".unicodeScalars, fonts: fonts))
    }

    @Test func colorsAndModes() {
        let red = RGBColor(red8: 0xFF, green8: 0, blue8: 0), blue = RGBColor(red8: 0, green8: 0, blue8: 0xFF)
        let port = port(depth: 32)
        port.foreColor = red
        port.move(to: Point(v: 12, h: 1))
        port.drawText("H".unicodeScalars, fonts: fonts)
        #expect(port.pixels?.color(at: Point(v: 5, h: 1)) == red)
        #expect(port.pixels?.color(at: Point(v: 5, h: 3)) == .white)
        // srcCopy draws the characters' cell in the background color.
        let copied = self.port(depth: 32)
        copied.backColor = blue
        copied.text.mode = .srcCopy
        copied.move(to: Point(v: 12, h: 1))
        copied.drawText("H".unicodeScalars, fonts: fonts)
        #expect(copied.pixels?.color(at: Point(v: 5, h: 3)) == blue)
        #expect(copied.pixels?.color(at: Point(v: 5, h: 1)) == .black)
        #expect(copied.pixels?.color(at: Point(v: 5, h: 30)) == .white)
    }

    @Test func clipping() {
        let port = port()
        port.clip(to: Rect(top: 0, left: 0, bottom: 16, right: 4))
        port.move(to: Point(v: 12, h: 1))
        port.drawText("HH".unicodeScalars, fonts: fonts)
        #expect(port.pixels?.color(at: Point(v: 5, h: 1)) == .black)
        #expect(port.pixels?.color(at: Point(v: 5, h: 5)) == .white)
        // The pen moves all the same.
        #expect(port.pen.location.h == 1 + 2 * 8)
    }

    @Test func registry() {
        let fonts = FontRegistry()
        #expect(fonts.number(of: "geneva") == 3)
        #expect(fonts.name(of: 21) == "Helvetica")
        #expect(fonts.name(of: FontRegistry.applicationFont) == "Geneva")
        #expect(fonts.number(of: "Nothing") == nil)
        #expect(fonts.face(family: 21) === SystemFont.shared)

        final class Named: FontFace {
            let familyName: String
            init(_ name: String) { familyName = name }
            func metrics(size: Int) -> FontMetrics { FontMetrics(ascent: 9, descent: 3, widMax: 9, leading: 1) }
            func glyph(for character: Unicode.Scalar, size: Int) -> GlyphImage? { .blank(advance: 5) }
        }
        let face = Named("Futura")
        let number = fonts.register(face)
        #expect(number >= 1024)
        #expect(fonts.number(of: "Futura") == number)
        #expect(fonts.face(family: number) === face)
        #expect(fonts.register(Named("Futura")) == number)

        // A host's lookup, for a classic name's substitute.
        let substitute = Named("Arial")
        let looked = FontRegistry { $0 == "Arial" ? substitute : nil }
        #expect(looked.face(family: 21) === substitute)
        let port = port()
        port.text.font = 21
        #expect(port.textWidth("abc".unicodeScalars, fonts: looked) == 15)
        #expect(port.fontInfo(fonts: looked).ascent == 9)
    }
}
