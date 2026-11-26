// Faces from outline fonts (TrueType, OpenType, Type 1 and the rest FreeType
// reads), rendered to 8-bit coverage. Built with the FreeType trait, which
// is on by default; without it there is only the built-in font.

#if FreeType
import CFreeType
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
    public init(data bytes: [UInt8], index: Int = 0) throws {
        guard let library = Self.library else { throw LoadError.libraryUnavailable }
        let copy = UnsafeMutableRawBufferPointer.allocate(byteCount: max(1, bytes.count), alignment: 16)
        bytes.withUnsafeBytes { if !bytes.isEmpty { copy.baseAddress!.copyMemory(from: $0.baseAddress!, byteCount: bytes.count) } }
        var face: FT_Face?
        guard FT_New_Memory_Face(library, copy.baseAddress!.assumingMemoryBound(to: FT_Byte.self), FT_Long(bytes.count), FT_Long(index), &face) == 0,
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
