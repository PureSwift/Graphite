// Faces from outline fonts (TrueType, OpenType, Type 1 and the rest FreeType
// reads), rendered to 8-bit coverage. Built with the FreeType trait, which
// is on by default; without it there is only the built-in font.

#if FreeType
import FreeTypeSwift
import protocol Foundation.ContiguousBytes
import struct Foundation.Data
import struct Foundation.URL
import Synchronization
import GraphiteBase

/// A font file loaded through swift-freetype. FreeType's faces aren't
/// thread-safe, so every call goes through one lock. The font's bytes are
/// kept as well, for its tables: a file loaded by path is mapped into
/// memory, not read.
public final class FreeTypeFace: FontFace, Sendable {

    public enum LoadError: Error, Equatable {
        case libraryUnavailable
        case unreadable
    }

    private static let library: FreeTypeLibrary? = try? FreeTypeLibrary()

    private let face: Mutex<FreeTypeSwift.FreeTypeFace>

    /// The font's sfnt tables; nil for a font that isn't one (Type 1, BDF).
    private let tables: SfntTables?

    public let familyName: String

    /// The style name the font says ("Regular", "Bold Italic").
    public let styleName: String

    /// The styles the font itself is: its bold and italic bits.
    public let styles: TextStyle

    /// A font in memory: `index` picks the face of a collection (a .ttc has
    /// several).
    public init(data bytes: some ContiguousBytes, index: Int = 0) throws {
        guard let library = Self.library else { throw LoadError.libraryUnavailable }
        let font = Data(zeroBased: bytes)
        let face: FreeTypeSwift.FreeTypeFace
        do {
            face = try library.face(data: font, index: index)
        } catch {
            throw LoadError.unreadable
        }
        tables = try? SfntTables(font: font, index: index)
        (familyName, styleName, styles) = Self.names(of: face, tables: tables)
        self.face = Mutex(face)
    }

    /// A font file by its path.
    public init(path: String, index: Int = 0) throws {
        guard let library = Self.library else { throw LoadError.libraryUnavailable }
        let face: FreeTypeSwift.FreeTypeFace
        do {
            face = try library.face(path: path, index: index)
        } catch {
            throw LoadError.unreadable
        }
        tables = (try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped))
            .flatMap { try? SfntTables(font: $0, index: index) }
        (familyName, styleName, styles) = Self.names(of: face, tables: tables)
        self.face = Mutex(face)
    }

    private static func names(of face: borrowing FreeTypeSwift.FreeTypeFace, tables: SfntTables?) -> (String, String, TextStyle) {
        let family = face.familyName.isEmpty ? "Unknown" : face.familyName
        let style = face.styleName
        if let tables { return (family, style, tables.styles) }
        // A font with no tables says its style in its name.
        var styles: TextStyle = []
        let lowered = style.lowercased()
        if lowered.contains("bold") { styles.insert(.bold) }
        if lowered.contains("italic") || lowered.contains("oblique") { styles.insert(.italic) }
        return (family, style, styles)
    }

    /// The font is its own plain face: bold and italic ones say so, and the
    /// rest are drawn from its glyphs.
    public func hasStyle(_ style: TextStyle) -> Bool {
        style == styles || style.isEmpty
    }

    /// Characters the font has a glyph for.
    public func contains(_ character: Unicode.Scalar) -> Bool {
        face.withLock { $0.glyphIndex(for: character) != 0 }
    }

    /// A table of an sfnt font by its tag; nil for a table it hasn't and for
    /// a font that isn't an sfnt (Type 1, say).
    public func table(_ tag: FourCharCode) -> [UInt8]? {
        tables?.table(tag)
    }

    /// Ascent, descent and the rest in ems, from the face's own numbers
    /// and its 'hhea', 'head', 'OS/2' and 'post' tables where it has them.
    /// Without an 'OS/2' table the average advance is half the maximum and
    /// the cap and x heights are the ascent and half of it, as with an
    /// 'OS/2' older than version 2.
    public var horizontalMetrics: HorizontalFontMetrics? {
        face.withLock { face in
            let em = face.unitsPerEM == 0 ? 1000.0 : Double(face.unitsPerEM)
            let ascent = Double(face.designAscender) / em
            var metrics = HorizontalFontMetrics(
                ascent: ascent,
                descent: Double(face.designDescender) / em,
                leading: max(0, Double(face.designLineHeight - face.designAscender + face.designDescender) / em))
            if let advance = tables?.maximumAdvance {
                metrics.maximumAdvance = Double(advance) / em
            } else if (try? face.setPixelSize(width: 0, height: UInt32(em))) != nil {
                // At a size of one em in pixels, a pixel is a font unit.
                metrics.maximumAdvance = face.maxAdvance / em
            }
            metrics.minimumLeftSideBearing = Double(tables?.minimumLeftSideBearing ?? 0) / em
            if let underline = tables?.underline {
                metrics.underlinePosition = Double(underline.position) / em
                metrics.underlineThickness = Double(underline.thickness) / em
            }
            metrics.averageAdvance = tables?.averageAdvance.map { Double($0) / em } ?? metrics.maximumAdvance / 2
            metrics.capHeight = tables?.capHeight.map { Double($0) / em } ?? ascent
            metrics.xHeight = tables?.xHeight.map { Double($0) / em } ?? ascent / 2
            metrics.italicAngle = tables?.italicAngle ?? 0
            return metrics
        }
    }

    public func metrics(size: Int) -> FontMetrics {
        face.withLock { face in
            guard (try? face.setPixelSize(width: 0, height: Self.pixelSize(size))) != nil else {
                return FontMetrics(ascent: 0, descent: 0, widMax: 0, leading: 0)
            }
            // FreeType's scaled metrics are whole numbers of 26.6 units, so
            // they're exact here; rounded up to whole pixels.
            let ascent = Int(face.ascender.rounded(.up))
            let descent = Int((-face.descender).rounded(.up))
            let height = Int(face.lineHeight.rounded(.up))
            return FontMetrics(ascent: Int16(clamping: ascent), descent: Int16(clamping: descent),
                               widMax: Int16(clamping: Int(face.maxAdvance.rounded(.up))),
                               leading: Int16(clamping: max(0, height - ascent - descent)))
        }
    }

    /// A character's image, rendered as coverage. Nil for a character the
    /// face hasn't, and for one whose bitmap is in a mode that isn't
    /// coverage (a color emoji's).
    public func glyph(for character: Unicode.Scalar, size: Int) -> GlyphImage? {
        face.withLock { face in
            guard (try? face.setPixelSize(width: 0, height: Self.pixelSize(size))) != nil else { return nil }
            let index = face.glyphIndex(for: character)
            guard index != 0, let glyph = try? face.glyph(at: index, flags: .render) else { return nil }
            let advance = Int(glyph.advanceX.rounded())
            guard let bitmap = glyph.bitmap, bitmap.width > 0, bitmap.rows > 0 else { return .blank(advance: advance) }
            let width = bitmap.width, height = bitmap.rows
            var coverage = [UInt8](repeating: 0, count: width * height)
            switch bitmap.pixelMode {
            case .mono:
                for row in 0 ..< height {
                    for column in 0 ..< width {
                        let byte = bitmap.pixels[row * bitmap.bytesPerRow + column / 8]
                        coverage[row * width + column] = byte & (0x80 >> UInt8(column % 8)) != 0 ? 255 : 0
                    }
                }
            case .gray:
                for row in 0 ..< height {
                    let start = row * bitmap.bytesPerRow
                    coverage.replaceSubrange(row * width ..< (row + 1) * width, with: bitmap.pixels[start ..< start + width])
                }
            default:
                return nil
            }
            return GlyphImage(width: width, height: height, left: bitmap.left, top: bitmap.top, coverage: coverage, advance: advance)
        }
    }

    /// The pixel size to ask FreeType for: 12 where none is asked for, as
    /// QuickDraw's default is.
    private static func pixelSize(_ size: Int) -> UInt32 {
        UInt32(clamping: size <= 0 ? 12 : size)
    }
}
#endif
