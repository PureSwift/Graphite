// Faces from outline fonts (TrueType, OpenType, Type 1 and the rest FreeType
// reads), rendered to 8-bit coverage. Built with the FreeType trait, which
// is on by default; without it there is only the built-in font.

#if FreeType
import CFreeType
import protocol Foundation.ContiguousBytes
import Synchronization
import GraphiteBase

/// A font file loaded through FreeType. FreeType's faces aren't thread-safe,
/// so every call goes through one lock.
public final class FreeTypeFace: FontFace, @unchecked Sendable {

    public enum LoadError: Error, Equatable {
        case libraryUnavailable
        case unreadable
    }

    nonisolated(unsafe) private static let library: FT_Library? = {
        var library: FT_Library?
        return FT_Init_FreeType(&library) == 0 ? library : nil
    }()

    private let lock = Mutex<Void>(())
    private let face: FT_Face
    /// The font's bytes, which FreeType reads from for as long as the face
    /// lives.
    private let data: UnsafeMutableRawBufferPointer?

    public let familyName: String

    /// The style name the font says ("Regular", "Bold Italic").
    public let styleName: String

    /// The styles the font itself is: its bold and italic bits.
    public let styles: TextStyle

    /// A font in memory: nil `index` is the file's first face (a .ttc has
    /// several).
    public init(data bytes: some ContiguousBytes, index: Int = 0) throws {
        guard let library = Self.library else { throw LoadError.libraryUnavailable }
        // FreeType reads from the bytes for as long as the face lives, so
        // they are copied.
        let count = bytes.withUnsafeBytes { $0.count }
        let copy = UnsafeMutableRawBufferPointer.allocate(byteCount: max(1, count), alignment: 16)
        bytes.withUnsafeBytes { if $0.count > 0 { copy.baseAddress!.copyMemory(from: $0.baseAddress!, byteCount: $0.count) } }
        var face: FT_Face?
        guard FT_New_Memory_Face(library, copy.baseAddress!.assumingMemoryBound(to: FT_Byte.self), FT_Long(count), FT_Long(index), &face) == 0,
              let face else {
            copy.deallocate()
            throw LoadError.unreadable
        }
        self.face = face
        data = copy
        (familyName, styleName, styles) = Self.names(of: face)
    }

    /// A font file by its path.
    public init(path: String, index: Int = 0) throws {
        guard let library = Self.library else { throw LoadError.libraryUnavailable }
        var face: FT_Face?
        guard FT_New_Face(library, path, FT_Long(index), &face) == 0, let face else { throw LoadError.unreadable }
        self.face = face
        data = nil
        (familyName, styleName, styles) = Self.names(of: face)
    }

    deinit {
        FT_Done_Face(face)
        data?.deallocate()
    }

    private static func names(of face: FT_Face) -> (String, String, TextStyle) {
        let family = face.pointee.family_name.map { String(cString: $0) } ?? "Unknown"
        let style = face.pointee.style_name.map { String(cString: $0) } ?? ""
        var styles: TextStyle = []
        if face.pointee.style_flags & FT_Long(FT_STYLE_FLAG_BOLD) != 0 { styles.insert(.bold) }
        if face.pointee.style_flags & FT_Long(FT_STYLE_FLAG_ITALIC) != 0 { styles.insert(.italic) }
        return (family, style, styles)
    }

    /// The font is its own plain face: bold and italic ones say so, and the
    /// rest are drawn from its glyphs.
    public func hasStyle(_ style: TextStyle) -> Bool {
        style == styles || style.isEmpty
    }

    /// Characters the font has a glyph for.
    public func contains(_ character: Unicode.Scalar) -> Bool {
        lock.withLock { _ in FT_Get_Char_Index(face, FT_ULong(character.value)) != 0 }
    }

    /// A table of an sfnt font by its tag; nil for a table it hasn't and for
    /// a font that isn't an sfnt (Type 1, say).
    public func table(_ tag: FourCharCode) -> [UInt8]? {
        lock.withLock { _ in
            var length: FT_ULong = 0
            guard FT_Load_Sfnt_Table(face, FT_ULong(tag.rawValue), 0, nil, &length) == 0 else { return nil }
            var bytes = [UInt8](repeating: 0, count: Int(length))
            guard FT_Load_Sfnt_Table(face, FT_ULong(tag.rawValue), 0, &bytes, &length) == 0 else { return nil }
            return bytes
        }
    }

    /// Ascent, descent and the rest in ems, from the face's own numbers
    /// and its 'OS/2' and 'post' tables where it has them. Without an
    /// 'OS/2' table the average advance is half the maximum and the cap
    /// and x heights are the ascent and half of it, as with an 'OS/2'
    /// older than version 2.
    public var horizontalMetrics: HorizontalFontMetrics? {
        lock.withLock { _ in
            let record = face.pointee
            let em = record.units_per_EM == 0 ? 1000.0 : Double(record.units_per_EM)
            let ascent = Double(record.ascender) / em
            var metrics = HorizontalFontMetrics(
                ascent: ascent,
                descent: Double(record.descender) / em,
                leading: max(0, Double(record.height - record.ascender + record.descender) / em),
                maximumAdvance: Double(record.max_advance_width) / em,
                minimumLeftSideBearing: Double(record.bbox.xMin) / em,
                underlinePosition: Double(record.underline_position) / em,
                underlineThickness: Double(record.underline_thickness) / em)
            if let table = FT_Get_Sfnt_Table(face, FT_SFNT_OS2) {
                let os2 = table.assumingMemoryBound(to: TT_OS2.self).pointee
                metrics.averageAdvance = Double(os2.xAvgCharWidth) / em
                metrics.capHeight = os2.version >= 2 ? Double(os2.sCapHeight) / em : ascent
                metrics.xHeight = os2.version >= 2 ? Double(os2.sxHeight) / em : ascent / 2
            } else {
                metrics.averageAdvance = metrics.maximumAdvance / 2
                metrics.capHeight = ascent
                metrics.xHeight = ascent / 2
            }
            if let table = FT_Get_Sfnt_Table(face, FT_SFNT_POST) {
                metrics.italicAngle = Double(table.assumingMemoryBound(to: TT_Postscript.self).pointee.italicAngle) / 65536
            }
            return metrics
        }
    }

    public func metrics(size: Int) -> FontMetrics {
        lock.withLock { _ in
            setSize(size)
            guard let metrics = face.pointee.size?.pointee.metrics else { return FontMetrics(ascent: 0, descent: 0, widMax: 0, leading: 0) }
            let ascent = Int((metrics.ascender + 63) >> 6)
            let descent = Int((-metrics.descender + 63) >> 6)
            let height = Int((metrics.height + 63) >> 6)
            return FontMetrics(ascent: Int16(clamping: ascent), descent: Int16(clamping: descent),
                               widMax: Int16(clamping: Int((metrics.max_advance + 63) >> 6)),
                               leading: Int16(clamping: max(0, height - ascent - descent)))
        }
    }

    public func glyph(for character: Unicode.Scalar, size: Int) -> GlyphImage? {
        lock.withLock { _ in
            setSize(size)
            let index = FT_Get_Char_Index(face, FT_ULong(character.value))
            guard index != 0, FT_Load_Glyph(face, index, FT_Int32(FT_LOAD_RENDER)) == 0,
                  let slot = face.pointee.glyph else { return nil }
            let bitmap = slot.pointee.bitmap
            let advance = Int((slot.pointee.advance.x + 32) >> 6)
            let width = Int(bitmap.width), height = Int(bitmap.rows)
            guard width > 0, height > 0, let buffer = bitmap.buffer else { return .blank(advance: advance) }
            var coverage = [UInt8](repeating: 0, count: width * height)
            let pitch = Int(bitmap.pitch)
            for row in 0 ..< height {
                let line = buffer + row * pitch
                for column in 0 ..< width {
                    switch Int32(bitmap.pixel_mode) {
                    case Int32(FT_PIXEL_MODE_MONO.rawValue):
                        coverage[row * width + column] = line[column / 8] & (0x80 >> UInt8(column % 8)) != 0 ? 255 : 0
                    default:
                        coverage[row * width + column] = line[column]
                    }
                }
            }
            return GlyphImage(width: width, height: height, left: Int(slot.pointee.bitmap_left), top: Int(slot.pointee.bitmap_top),
                              coverage: coverage, advance: advance)
        }
    }

    /// Sets the pixel size, 12 where none is asked for as QuickDraw's
    /// default is. Called with the lock held.
    private func setSize(_ size: Int) {
        _ = FT_Set_Pixel_Sizes(face, 0, FT_UInt(size <= 0 ? 12 : size))
    }
}
#endif
