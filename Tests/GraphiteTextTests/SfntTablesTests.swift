import struct Foundation.Data
import Testing
import GraphiteBase
import GraphiteText

@Suite struct SfntTablesTests {

    /// A table of `size` zero bytes with fields written at offsets.
    private func table(_ size: Int, _ fields: [(Int, UInt32, Int)] = []) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size)
        for (offset, value, width) in fields {
            for index in 0 ..< width { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> UInt32(8 * (width - 1 - index))) }
        }
        return bytes
    }

    private func head(unitsPerEm: UInt32 = 2048, xMin: Int16 = -100, macStyle: UInt32 = 0) -> [UInt8] {
        table(54, [(18, unitsPerEm, 2), (36, UInt32(UInt16(bitPattern: xMin)), 2), (44, macStyle, 2)])
    }

    private let hhea = [UInt8](repeating: 0, count: 10) + [0x09, 0xC4] + [UInt8](repeating: 0, count: 24)   // advanceWidthMax 2500

    private func os2(version: UInt32 = 2, selection: UInt32 = 0) -> [UInt8] {
        table(96, [(0, version, 2), (2, 1100, 2), (62, selection, 2), (86, 1000, 2), (88, 1400, 2)])
    }

    private func post() -> [UInt8] {
        table(32, [(4, UInt32(bitPattern: Int32(-12 * 65536)), 4), (8, UInt32(UInt16(bitPattern: -150)), 2), (10, 90, 2)])
    }

    /// An sfnt file: its directory, then the tables one after another. `base`
    /// is where the directory starts, for a face of a collection.
    private func sfnt(_ tables: [(FourCharCode, [UInt8])], base: Int = 0) -> [UInt8] {
        var writer = BigEndianWriter()
        writer.write(UInt32(0x0001_0000))
        writer.write(UInt16(tables.count))
        writer.writeZeros(6)
        var offset = base + 12 + 16 * tables.count
        for (tag, bytes) in tables {
            writer.write(tag.rawValue)
            writer.write(UInt32(0))
            writer.write(UInt32(offset))
            writer.write(UInt32(bytes.count))
            offset += bytes.count
        }
        for (_, bytes) in tables { writer.write(bytes: bytes) }
        return writer.bytes
    }

    private var font: [UInt8] {
        sfnt([("head", head(macStyle: 0)), ("hhea", hhea), ("OS/2", os2()), ("post", post())])
    }

    @Test func readsTheDirectoryAndTables() throws {
        let tables = try SfntTables(font: font)
        #expect(tables.tags == ["OS/2", "head", "hhea", "post"])
        #expect(tables.table("head") == head())
        #expect(tables.table("post") == post())
        #expect(tables.table("cmap") == nil)
        #expect(tables.hasOS2)
    }

    @Test func readsTheFields() throws {
        let tables = try SfntTables(font: font)
        #expect(tables.unitsPerEm == 2048)
        #expect(tables.maximumAdvance == 2500)
        #expect(tables.minimumLeftSideBearing == -100)
        #expect(tables.underline?.position == -150)
        #expect(tables.underline?.thickness == 90)
        #expect(tables.italicAngle == -12)
        #expect(tables.averageAdvance == 1100)
        #expect(tables.capHeight == 1400)
        #expect(tables.xHeight == 1000)
    }

    @Test func missingTablesGiveNoFields() throws {
        let tables = try SfntTables(font: sfnt([("head", head())]))
        #expect(tables.unitsPerEm == 2048)
        #expect(tables.maximumAdvance == nil)
        #expect(tables.underline == nil)
        #expect(tables.italicAngle == nil)
        #expect(tables.averageAdvance == nil)
        #expect(tables.capHeight == nil)
        #expect(!tables.hasOS2)
        #expect(try SfntTables(font: sfnt([])).unitsPerEm == nil)
    }

    @Test func oldOS2TablesHaveNoCapOrXHeight() throws {
        let tables = try SfntTables(font: sfnt([("OS/2", os2(version: 1))]))
        #expect(tables.averageAdvance == 1100)
        #expect(tables.capHeight == nil)
        #expect(tables.xHeight == nil)
    }

    @Test func stylesFromMacStyleAndSelection() throws {
        func styles(macStyle: UInt32, selection: UInt32?) throws -> TextStyle {
            var tables: [(FourCharCode, [UInt8])] = [("head", head(macStyle: macStyle))]
            if let selection { tables.append(("OS/2", os2(selection: selection))) }
            return try SfntTables(font: sfnt(tables)).styles
        }
        #expect(try styles(macStyle: 0, selection: nil) == [])
        #expect(try styles(macStyle: 1, selection: nil) == .bold)
        #expect(try styles(macStyle: 2, selection: nil) == .italic)
        #expect(try styles(macStyle: 3, selection: nil) == [.bold, .italic])
        #expect(try styles(macStyle: 0, selection: 0x20) == .bold)
        #expect(try styles(macStyle: 0, selection: 0x01) == .italic)
        #expect(try styles(macStyle: 0, selection: 0x200) == .italic)
        #expect(try styles(macStyle: 0, selection: 0x40) == [])
    }

    @Test func tablesPastTheEndAreNotThere() throws {
        var bytes = font
        // Cut the file in the middle of the last table.
        bytes.removeLast(10)
        let tables = try SfntTables(font: bytes)
        #expect(tables.table("head") == head())
        #expect(tables.table("post") == nil)
    }

    @Test func aCollectionsFacesAreEachTheirOwn() throws {
        // A 'ttcf' header of two faces, then each face's directory and tables.
        let plain = sfnt([("head", head(macStyle: 0))], base: 20)
        var writer = BigEndianWriter()
        writer.write(FourCharCode("ttcf").rawValue)
        writer.write(UInt32(0x0001_0000))
        writer.write(UInt32(2))
        let firstBase = 20
        let secondBase = firstBase + plain.count
        writer.write(UInt32(firstBase))
        writer.write(UInt32(secondBase))
        let bold = sfnt([("head", head(macStyle: 1))], base: secondBase)
        let bytes = writer.bytes + plain + bold
        #expect(try SfntTables(font: bytes, index: 0).styles == [])
        #expect(try SfntTables(font: bytes, index: 1).styles == .bold)
        #expect(throws: MacError.parameter) { try SfntTables(font: bytes, index: 2) }
        #expect(throws: MacError.parameter) { try SfntTables(font: bytes, index: -1) }
    }

    @Test func fontsFromAnyBytes() throws {
        let bytes = font
        let expected = try SfntTables(font: bytes).tags
        #expect(try SfntTables(font: Data(bytes)).tags == expected)
        #expect(try SfntTables(font: Data([1, 2, 3] + bytes)[3...]).tags == expected)
        #expect(try bytes.withUnsafeBytes { try SfntTables(font: $0) }.tags == expected)
    }

    @Test func otherBytesAreAParameterError() {
        #expect(throws: MacError.parameter) { try SfntTables(font: [UInt8]()) }
        #expect(throws: MacError.parameter) { try SfntTables(font: Array("not a font at all".utf8)) }
        #expect(throws: MacError.parameter) { try SfntTables(font: [0, 1, 0]) }
    }

    @Test func truncatedFontsNeverTrap() {
        let bytes = font
        for length in 0 ... bytes.count {
            if let tables = try? SfntTables(font: bytes.prefix(length)) {
                _ = (tables.tags, tables.styles, tables.unitsPerEm, tables.capHeight, tables.underline)
            }
        }
    }
}
