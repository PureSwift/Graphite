// The tables of an sfnt font file (TrueType, OpenType, a .ttc collection's
// faces): the directory read from the font's bytes, and the few fields of
// 'head', 'hhea', 'OS/2' and 'post' that ATS gives programs. Read in place,
// so a font file mapped into memory costs pages as they are used.

import protocol Foundation.ContiguousBytes
import struct Foundation.Data
import GraphiteBase

public struct SfntTables: Sendable {

    private let font: Data

    /// Where each table is in the font's bytes.
    private var directory: [FourCharCode: Range<Int>] = [:]

    /// The tables of a font's bytes: parameter error for bytes that aren't
    /// an sfnt, or a collection without that face. `index` picks the face
    /// of a collection.
    public init(font bytes: some ContiguousBytes, index: Int = 0) throws(MacError) {
        font = Data(zeroBased: bytes)
        var reader = BigEndianReader(font)
        do {
            var tag = try reader.read(UInt32.self)
            if tag == FourCharCode("ttcf").rawValue {
                try reader.skip(4)                                      // version
                let count = Int(try reader.read(UInt32.self))
                guard index >= 0, index < count else { throw MacError.parameter }
                try reader.seek(to: Int(try reader.peek(UInt32.self, at: 12 + 4 * index)))
                tag = try reader.read(UInt32.self)
            }
            guard tag == 0x0001_0000 || [FourCharCode("true"), "OTTO", "typ1"].contains(FourCharCode(tag)) else {
                throw MacError.parameter
            }
            let count = Int(try reader.read(UInt16.self))
            try reader.skip(6)                                          // searchRange, entrySelector, rangeShift
            for _ in 0 ..< count {
                let name = FourCharCode(try reader.read(UInt32.self))
                try reader.skip(4)                                      // checksum
                let offset = Int(try reader.read(UInt32.self))
                let length = Int(try reader.read(UInt32.self))
                // A table past the end of the file is not there; the first of a tag wins.
                guard offset <= font.count, length <= font.count - offset, directory[name] == nil else { continue }
                directory[name] = offset ..< offset + length
            }
        } catch let error as MacError {
            throw error
        } catch {
            throw .parameter
        }
    }

    /// The tables' tags, sorted.
    public var tags: [FourCharCode] { directory.keys.sorted() }

    /// A table's bytes, copied; nil if the font has none of the tag.
    public func table(_ tag: FourCharCode) -> [UInt8]? {
        directory[tag].map { Array(font[font.startIndex + $0.lowerBound ..< font.startIndex + $0.upperBound]) }
    }

    /// A field of a table at an offset, as many bytes as `T` is; nil if the
    /// table or the field isn't there.
    private func field<T: FixedWidthInteger>(_ tag: FourCharCode, at offset: Int, as type: T.Type = T.self) -> T? {
        guard let range = directory[tag], offset + MemoryLayout<T>.size <= range.count else { return nil }
        let reader = BigEndianReader(font)
        return try? reader.peek(T.self, at: range.lowerBound + offset)
    }

    /// Font units to the em ('head').
    public var unitsPerEm: Int? { field("head", at: 18, as: UInt16.self).map(Int.init) }

    /// The bold and italic the font says it is: 'head''s macStyle, and
    /// 'OS/2''s fsSelection (italic, bold, oblique).
    public var styles: TextStyle {
        var styles: TextStyle = []
        let macStyle = field("head", at: 44, as: UInt16.self) ?? 0
        let selection = field("OS/2", at: 62, as: UInt16.self) ?? 0
        if macStyle & 1 != 0 || selection & 0x20 != 0 { styles.insert(.bold) }
        if macStyle & 2 != 0 || selection & 0x01 != 0 || selection & 0x200 != 0 { styles.insert(.italic) }
        return styles
    }

    /// The widest advance in font units ('hhea').
    public var maximumAdvance: Int? { field("hhea", at: 10, as: UInt16.self).map(Int.init) }

    /// The left edge of the font's bounding box in font units ('head').
    public var minimumLeftSideBearing: Int? { field("head", at: 36, as: Int16.self).map(Int.init) }

    /// The underline's position (below the baseline, negative) and
    /// thickness in font units ('post').
    public var underline: (position: Int, thickness: Int)? {
        guard let position = field("post", at: 8, as: Int16.self), let thickness = field("post", at: 10, as: Int16.self) else { return nil }
        return (Int(position), Int(thickness))
    }

    /// The italic angle in degrees ('post'); negative leans right.
    public var italicAngle: Double? { field("post", at: 4, as: Int32.self).map { Double($0) / 65536 } }

    /// The average character width in font units ('OS/2').
    public var averageAdvance: Int? { field("OS/2", at: 2, as: Int16.self).map(Int.init) }

    /// The height of capitals in font units; nil unless the 'OS/2' table is
    /// version 2 or later.
    public var capHeight: Int? { field("OS/2", at: 0, as: UInt16.self).flatMap { $0 >= 2 ? field("OS/2", at: 88, as: Int16.self).map(Int.init) : nil } }

    /// The height of the lowercase x in font units; nil unless the 'OS/2'
    /// table is version 2 or later.
    public var xHeight: Int? { field("OS/2", at: 0, as: UInt16.self).flatMap { $0 >= 2 ? field("OS/2", at: 86, as: Int16.self).map(Int.init) : nil } }

    /// Whether the font has an 'OS/2' table.
    public var hasOS2: Bool { directory["OS/2"] != nil }
}
