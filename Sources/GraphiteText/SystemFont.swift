// The built-in face: SystemFontGlyphs' bitmap at 12 points, scaled by whole
// pixels to other sizes (24 is twice as large, 6 half), for text when no
// other face is there.

import GraphiteBase

public final class SystemFont: FontFace {

    public static let shared = SystemFont()

    public let familyName = "Chicago"

    public init() {}

    /// Its size, whatever is asked for 0.
    public static var nativeSize: Int { 12 }

    private func scale(_ size: Int) -> (numerator: Int, denominator: Int) {
        let size = size <= 0 ? Self.nativeSize : size
        return (size, Self.nativeSize)
    }

    public func metrics(size: Int) -> FontMetrics {
        let (n, d) = scale(size)
        let widest = SystemFontGlyphs.glyphs.map(\.width).max() ?? 0
        return FontMetrics(
            ascent: Int16(SystemFontGlyphs.ascent * n / d),
            descent: Int16(max(1, SystemFontGlyphs.descent * n / d)),
            widMax: Int16((widest + SystemFontGlyphs.characterSpacing) * n / d),
            leading: 0
        )
    }

    /// Whether the font has a character: printable ASCII; it draws others
    /// as "?".
    private func hasGlyph(_ character: Unicode.Scalar) -> Bool {
        let index = Int(character.value) - SystemFontGlyphs.firstCharacter
        return index >= 0 && index < SystemFontGlyphs.glyphs.count
    }

    /// A character's code, which names its glyph; 0 for one it hasn't.
    public func glyphID(for character: Unicode.Scalar) -> UInt16 {
        hasGlyph(character) ? UInt16(character.value) : 0
    }

    /// The ink of a character's glyph; nil for one the font hasn't, which
    /// it draws as "?".
    public func glyphMetrics(for character: Unicode.Scalar, size: Int) -> GlyphMetrics? {
        hasGlyph(character) ? glyph(for: character, size: size).map(GlyphMetrics.init(image:)) : nil
    }

    /// A printable ASCII character's glyph; others are "?", as the
    /// original draws them.
    public func glyph(for character: Unicode.Scalar, size: Int) -> GlyphImage? {
        var index = Int(character.value) - SystemFontGlyphs.firstCharacter
        if index < 0 || index >= SystemFontGlyphs.glyphs.count {
            index = Int(UInt8(ascii: "?")) - SystemFontGlyphs.firstCharacter
        }
        let glyph = SystemFontGlyphs.glyphs[index]
        let (n, d) = scale(size)
        let width = 16 * n / d, height = SystemFontGlyphs.rows * n / d
        guard width > 0, height > 0 else { return .blank(advance: (glyph.width + SystemFontGlyphs.characterSpacing) * n / d) }
        var coverage = [UInt8](repeating: 0, count: width * height)
        for row in 0 ..< height {
            let bits = glyph.rows[row * d / n]
            for column in 0 ..< width where bits & (1 << UInt16(column * d / n)) != 0 {
                coverage[row * width + column] = 255
            }
        }
        return GlyphImage(
            width: width,
            height: height,
            left: -SystemFontGlyphs.leftMargin * n / d,
            top: SystemFontGlyphs.ascent * n / d,
            coverage: coverage,
            advance: (glyph.width + SystemFontGlyphs.characterSpacing) * n / d
        )
    }
}
