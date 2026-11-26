// QuickDraw's text: DrawString, DrawText and DrawChar at the pen in the
// port's font, face, size and mode, and TextWidth, StringWidth, CharWidth
// and GetFontInfo. Styles a face hasn't are drawn from its plain glyphs as
// QuickDraw drew them: bold twice a pixel apart and a pixel wider, italic
// slanted a pixel in four, underline below the baseline, outline and shadow
// around the glyph, condense and extend a pixel narrower and wider.

import GraphiteBase
import GraphiteQuickDraw

public extension Port {

    /// GetFontInfo for the port's font, size and face.
    func fontInfo(fonts: FontRegistry) -> FontMetrics {
        let style = TextStyle(rawValue: text.face)
        var metrics = fonts.face(family: text.font, style: style).metrics(size: Int(text.size))
        if style.contains(.italic) { metrics.widMax += metrics.ascent / 4 }
        if style.contains(.shadow) {
            metrics.descent += 1
            metrics.widMax += 2
        } else if style.contains(.outline) {
            metrics.widMax += 1
        }
        return metrics
    }

    /// TextWidth and StringWidth: how far drawing the characters moves the
    /// pen, in whole pixels.
    func textWidth(_ characters: some Sequence<Unicode.Scalar>, fonts: FontRegistry) -> Int {
        let layout = layOut(characters, fonts: fonts)
        return Int(layout.width.rounded())
    }

    /// TextWidth of MacRoman text, as programs pass it.
    func textWidth(macRoman bytes: some Sequence<UInt8>, fonts: FontRegistry) -> Int {
        textWidth(MacRoman.decode(bytes).unicodeScalars, fonts: fonts)
    }

    /// DrawText, DrawString and DrawChar: the characters at the pen, which
    /// moves past them.
    func drawText(_ characters: some Sequence<Unicode.Scalar>, fonts: FontRegistry) {
        let layout = layOut(characters, fonts: fonts)
        let origin = pen.location
        defer { pen.location.h &+= Int16(clamping: Int(layout.width.rounded())) }
        guard let pixels else { return }
        let style = layout.style
        let drawable = drawableRegion
        // srcCopy draws the characters' cell in the background color first.
        if text.mode.base == .srcCopy || text.mode.base == .notSrcCopy {
            let metrics = layout.face.metrics(size: Int(text.size))
            let cell = Rect(top: origin.v &- metrics.ascent, left: origin.h, bottom: origin.v &+ metrics.descent,
                            right: origin.h &+ Int16(clamping: Int(layout.width.rounded())))
            draw(Region(rect: cell), pattern: .white, mode: .patCopy)
        }
        for placed in layout.glyphs {
            var mask = Mask(placed.glyph, synthesizing: style)
            if style.contains(.outline) || style.contains(.shadow) { mask = mask.outlined(shadow: style.contains(.shadow)) }
            let left = Int(origin.h) + Int(placed.x.rounded()) + mask.left
            let top = Int(origin.v) - mask.top
            for row in 0 ..< mask.height {
                for column in 0 ..< mask.width {
                    let coverage = mask.coverage[row * mask.width + column]
                    guard coverage > 0 else { continue }
                    let point = Point(v: Int16(clamping: top + row), h: Int16(clamping: left + column))
                    guard drawable.contains(point) else { continue }
                    plot(coverage, at: point, in: pixels)
                }
            }
        }
        if style.contains(.underline) {
            let y = origin.v &+ 1
            let line = Rect(top: y, left: origin.h, bottom: y &+ 1, right: origin.h &+ Int16(clamping: Int(layout.width.rounded())))
            for point in Region(rect: line).intersection(drawable).rectangles.flatMap(points) { plot(255, at: point, in: pixels) }
        }
    }

    /// DrawString of MacRoman bytes, a Pascal string's.
    func drawText(macRoman bytes: some Sequence<UInt8>, fonts: FontRegistry) {
        drawText(MacRoman.decode(bytes).unicodeScalars, fonts: fonts)
    }

    // MARK: Layout

    private struct Placed {
        var glyph: GlyphImage
        var x: Double
    }

    private struct Layout {
        var face: any FontFace
        var style: TextStyle
        var glyphs: [Placed]
        var width: Double
    }

    /// Where each character goes from the pen: its advance, the style's
    /// extra, CharExtra for every one and SpaceExtra for spaces.
    private func layOut(_ characters: some Sequence<Unicode.Scalar>, fonts: FontRegistry) -> Layout {
        let style = TextStyle(rawValue: text.face)
        let face = fonts.face(family: text.font, style: style)
        let synthesized = TextStyle(rawValue: style.rawValue & ~(face.hasStyle(style) ? style.rawValue : 0))
        var extra = 0.0
        if synthesized.contains(.bold) { extra += 1 }
        if synthesized.contains(.condense) { extra -= 1 }
        if synthesized.contains(.extend) { extra += 1 }
        if synthesized.contains(.shadow) { extra += 2 } else if synthesized.contains(.outline) { extra += 1 }
        let characterExtra = Double(text.characterExtra.rawValue) / 65536
        let spaceExtra = Double(text.spaceExtra.rawValue) / 65536
        var x = 0.0
        var glyphs: [Placed] = []
        for character in characters {
            guard let glyph = face.glyph(for: character, size: Int(text.size)) ?? SystemFont.shared.glyph(for: character, size: Int(text.size)) else { continue }
            glyphs.append(Placed(glyph: glyph, x: x))
            x += Double(glyph.advance) + extra + characterExtra + (character == " " ? spaceExtra : 0)
        }
        return Layout(face: face, style: synthesized, glyphs: glyphs, width: max(0, x))
    }

    // MARK: Pixels

    /// A glyph's coverage drawn in the text mode: on direct pixels in srcOr,
    /// blended by its coverage; otherwise solid where it is half covered.
    private func plot(_ coverage: UInt8, at point: Point, in pixels: PixelBuffer) {
        guard let existing = pixels.color(at: point) else { return }
        let mode = text.mode.base
        if !pixels.format.isIndexed, mode == .srcOr || mode == .srcCopy || mode == .grayishTextOr {
            let weight = UInt32(coverage)
            func mix(_ a: UInt16, _ b: UInt16) -> UInt16 { UInt16((UInt32(a) * weight + UInt32(b) * (255 - weight)) / 255) }
            pixels.setColor(RGBColor(red: mix(foreColor.red, existing.red), green: mix(foreColor.green, existing.green),
                                     blue: mix(foreColor.blue, existing.blue)), at: point)
            return
        }
        guard coverage >= 128 else { return }
        let color = text.mode.combine(isForeground: true, drawn: foreColor, existing: existing, fore: foreColor, back: backColor, opColor: opColor)
        pixels.setColor(color, at: point)
    }

    private func points(_ rect: Rect) -> [Point] {
        (rect.top ..< rect.bottom).flatMap { v in (rect.left ..< rect.right).map { Point(v: v, h: $0) } }
    }
}

/// A glyph's coverage with the styles drawn from it.
private struct Mask {
    var width: Int
    var height: Int
    var left: Int
    var top: Int
    var coverage: [UInt8]

    init(_ glyph: GlyphImage, synthesizing style: TextStyle) {
        let slant = style.contains(.italic) ? (glyph.top + 3) / 4 : 0
        let bold = style.contains(.bold) ? 1 : 0
        width = glyph.width + slant + bold
        height = glyph.height
        left = glyph.left
        top = glyph.top
        coverage = [UInt8](repeating: 0, count: max(0, width * height))
        for row in 0 ..< glyph.height {
            // Italic: a pixel to the right for every four above the baseline.
            let shift = style.contains(.italic) ? max(0, (glyph.top - row) / 4) : 0
            for column in 0 ..< glyph.width {
                let value = glyph.coverage(column: column, row: row)
                guard value > 0 else { continue }
                for offset in 0 ... bold {
                    let index = row * width + column + shift + offset
                    coverage[index] = max(coverage[index], value)
                }
            }
        }
    }

    /// The pixels around the glyph and not in it, and for shadow those a
    /// pixel below and right as well.
    func outlined(shadow: Bool) -> Mask {
        let grow = shadow ? 2 : 1
        var result = Mask(width: width + 2 * grow, height: height + 2 * grow, left: left - grow, top: top + grow,
                          coverage: [UInt8](repeating: 0, count: (width + 2 * grow) * (height + 2 * grow)))
        func covered(_ column: Int, _ row: Int) -> Bool {
            column >= 0 && row >= 0 && column < width && row < height && coverage[row * width + column] >= 128
        }
        for row in 0 ..< result.height {
            for column in 0 ..< result.width {
                let x = column - grow, y = row - grow
                guard !covered(x, y) else { continue }
                var near = false
                for dy in -1 ... (shadow ? 2 : 1) {
                    for dx in -1 ... (shadow ? 2 : 1) where covered(x - dx, y - dy) { near = true }
                }
                if near { result.coverage[row * result.width + column] = 255 }
            }
        }
        return result
    }

    private init(width: Int, height: Int, left: Int, top: Int, coverage: [UInt8]) {
        self.width = width
        self.height = height
        self.left = left
        self.top = top
        self.coverage = coverage
    }
}
