// Fonts as QuickDraw and ATSUI draw them: a face renders a character at a
// size as a glyph image of coverage, 0 to 255 a pixel, placed from the pen
// on the baseline; its metrics are FontInfo's.

import GraphiteBase

/// FontInfo: a font's ascent and descent above and below the baseline, its
/// widest character, and the space between lines, in pixels.
public struct FontMetrics: Hashable, Sendable {

    public var ascent: Int16
    public var descent: Int16
    public var widMax: Int16
    public var leading: Int16

    public init(ascent: Int16, descent: Int16, widMax: Int16, leading: Int16) {
        self.ascent = ascent
        self.descent = descent
        self.widMax = widMax
        self.leading = leading
    }

    /// A line's height: ascent, descent and leading.
    public var lineHeight: Int { Int(ascent) + Int(descent) + Int(leading) }
}

/// QuickDraw's styles, TextFace's bits.
public struct TextStyle: OptionSet, Hashable, Sendable {

    public var rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static var bold: TextStyle { TextStyle(rawValue: 1) }
    public static var italic: TextStyle { TextStyle(rawValue: 2) }
    public static var underline: TextStyle { TextStyle(rawValue: 4) }
    public static var outline: TextStyle { TextStyle(rawValue: 8) }
    public static var shadow: TextStyle { TextStyle(rawValue: 16) }
    public static var condense: TextStyle { TextStyle(rawValue: 32) }
    public static var extend: TextStyle { TextStyle(rawValue: 64) }
}

/// A character's image: its coverage, row after row, `width` by `height`,
/// with its top left `left` pixels right of the pen and `top` above the
/// baseline; and how far the pen moves after it.
public struct GlyphImage: Hashable, Sendable {

    public var width: Int
    public var height: Int
    public var left: Int
    public var top: Int
    public var coverage: [UInt8]
    public var advance: Int

    public init(width: Int, height: Int, left: Int, top: Int, coverage: [UInt8], advance: Int) {
        self.width = width
        self.height = height
        self.left = left
        self.top = top
        self.coverage = coverage
        self.advance = advance
    }

    /// A glyph that draws nothing and moves the pen.
    public static func blank(advance: Int) -> GlyphImage {
        GlyphImage(width: 0, height: 0, left: 0, top: 0, coverage: [], advance: advance)
    }

    public func coverage(column: Int, row: Int) -> UInt8 {
        coverage[row * width + column]
    }
}

/// A typeface: its characters' images and metrics at any size.
public protocol FontFace: AnyObject, Sendable {

    /// The family's name: "Geneva", "Helvetica".
    var familyName: String { get }

    /// Whether it draws the style itself; the styles it doesn't are drawn
    /// from its plain glyphs.
    func hasStyle(_ style: TextStyle) -> Bool

    func metrics(size: Int) -> FontMetrics

    /// A character's image; nil for one the face hasn't.
    func glyph(for character: Unicode.Scalar, size: Int) -> GlyphImage?

    /// An sfnt table's bytes by its tag ('head', 'name', 'OS/2'), as
    /// ATSFontGetTable reads them; nil where the face has no such table,
    /// as a bitmap font has none.
    func table(_ tag: FourCharCode) -> [UInt8]?

    /// The font's metrics in ems, as ATSFontGetHorizontalMetrics gives them;
    /// nil for a face that isn't an outline font.
    var horizontalMetrics: HorizontalFontMetrics? { get }

    /// A character's glyph ID, as ATSUI's layout records name glyphs; 0 for
    /// a character the face hasn't.
    func glyphID(for character: Unicode.Scalar) -> UInt16

    /// A character's metrics at a size, with fractions of a pixel where the
    /// face has them; nil for a character it hasn't.
    func glyphMetrics(for character: Unicode.Scalar, size: Int) -> GlyphMetrics?
}

public extension FontFace {
    func hasStyle(_ style: TextStyle) -> Bool { style.isEmpty }
    func table(_ tag: FourCharCode) -> [UInt8]? { nil }
    var horizontalMetrics: HorizontalFontMetrics? { nil }

    /// A face with no glyph numbers of its own names its glyphs by their
    /// characters.
    func glyphID(for character: Unicode.Scalar) -> UInt16 {
        glyph(for: character, size: 12) == nil ? 0 : UInt16(min(character.value, 0xFFFE))
    }

    /// The glyph's image, whole pixels, as its metrics.
    func glyphMetrics(for character: Unicode.Scalar, size: Int) -> GlyphMetrics? {
        glyph(for: character, size: size).map(GlyphMetrics.init(image:))
    }
}
