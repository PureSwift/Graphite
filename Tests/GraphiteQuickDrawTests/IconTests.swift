import Testing
import GraphiteBase
import GraphiteQuickDraw

@Suite struct IconTests {

    /// A '#' member: a 1-bit image of the pixels `isSet` says, then a mask
    /// of the pixels `isMasked` says.
    private func bitmapMember(size: Int, isSet: (Int, Int) -> Bool, isMasked: (Int, Int) -> Bool) -> [UInt8] {
        func bits(_ test: (Int, Int) -> Bool) -> [UInt8] {
            (0 ..< size * size / 8).map { byte in
                (0 ..< 8).reduce(UInt8(0)) { value, bit in
                    let index = byte * 8 + bit
                    return test(index / size, index % size) ? value | (0x80 >> UInt8(bit)) : value
                }
            }
        }
        return bits(isSet) + bits(isMasked)
    }

    @Test func oneBitIcons() throws {
        // The left half black, the top half masked.
        let family = IconFamily(members: ["ICN#": bitmapMember(size: 32, isSet: { _, column in column < 16 }, isMasked: { row, _ in row < 16 })])
        let image = try #require(family.image(size: 32))
        #expect(image.value(column: 0, row: 0) == 0xFF00_0000)
        #expect(image.value(column: 20, row: 0) == 0xFFFF_FFFF)
        #expect(image.value(column: 0, row: 20) >> 24 == 0)
        #expect(family.image(size: 16) == nil)
        #expect(family.sizes == [32])
    }

    @Test func indexedIconsUseTheSystemTables() throws {
        var icl8 = [UInt8](repeating: 0, count: 1024)
        icl8[0] = 255                                           // black
        icl8[1] = 215                                           // the first red of the ramp
        var icl4 = [UInt8](repeating: 0, count: 512)
        icl4[0] = 0x3F                                          // red, then black
        let mask = bitmapMember(size: 32, isSet: { _, _ in false }, isMasked: { _, _ in true })
        let eight = try #require(IconFamily(members: ["icl8": icl8, "ICN#": mask]).image(size: 32))
        #expect(eight.value(column: 0, row: 0) == 0xFF00_0000)
        #expect(eight.value(column: 1, row: 0) == 0xFFEE_0000)
        #expect(eight.value(column: 2, row: 0) == 0xFFFF_FFFF)
        let four = try #require(IconFamily(members: ["icl4": icl4, "ICN#": mask]).image(size: 32))
        #expect(four.value(column: 0, row: 0) == 0xFFDD_0806)
        #expect(four.value(column: 1, row: 0) == 0xFF00_0000)
        // The color member wins over the 1-bit one.
        #expect(IconFamily(members: ["icl8": icl8, "icl4": icl4, "ICN#": mask]).image(size: 32)?.value(column: 1, row: 0) == 0xFFEE_0000)
    }

    @Test func thirtyTwoBitIcons() throws {
        // A 16×16 'is32': each plane one run of 256 (0x80 + 128 - 3 = 253
        // repeats, twice, then 3 more).
        func plane(_ value: UInt8) -> [UInt8] { [0xFF, value, 0xFF, value, 0x80, value] }
        let packed = plane(0x11) + plane(0x22) + plane(0x33)
        let mask = [UInt8](repeating: 0x80, count: 256)
        let image = try #require(IconFamily(members: ["is32": packed, "s8mk": mask]).image(size: 16))
        #expect(image.value(column: 15, row: 15) == 0x8011_2233)
        // Unpacked: four bytes a pixel.
        let unpacked: [UInt8] = (0 ..< 256).flatMap { _ -> [UInt8] in [0, 0x44, 0x55, 0x66] }
        #expect(IconFamily(members: ["is32": unpacked]).image(size: 16)?.value(column: 3, row: 3) == 0xFF44_5566)
        // Too short to be a whole image.
        #expect(IconFamily(members: ["is32": [0x05, 1, 2]]).image(size: 16) == nil)
    }

    @Test func icnsFiles() throws {
        func member(_ type: FourCharCode, _ bytes: [UInt8]) -> [UInt8] {
            var writer = BigEndianWriter()
            writer.write(type.rawValue)
            writer.write(UInt32(bytes.count + 8))
            writer.write(bytes: bytes)
            return writer.bytes
        }
        let body = member("ics#", bitmapMember(size: 16, isSet: { _, _ in true }, isMasked: { _, _ in true }))
            // 128 × 128 a plane: 127 runs of 130 (0xFF - 125), three planes.
            + member("it32", [0, 0, 0, 0] + Array(repeating: [UInt8(0xFF), 0x77], count: 127 * 3).flatMap { $0 })
        var file = BigEndianWriter()
        file.write(FourCharCode("icns").rawValue)
        file.write(UInt32(body.count + 8))
        file.write(bytes: body)
        let family = try IconFamily(icns: file.bytes)
        #expect(family.members.keys.sorted() == ["ics#", "it32"])
        #expect(family.image(size: 16)?.value(column: 0, row: 0) == 0xFF00_0000)
        #expect(family.image(size: 128)?.value(column: 127, row: 127) == 0xFF77_7777)
        #expect(throws: MacError.parameter) { try IconFamily(icns: [0, 1, 2, 3]) }
    }

    @Test func iconResourcesWithoutMasks() throws {
        let icon = [UInt8](repeating: 0xFF, count: 128)
        let image = try #require(IconFamily(members: ["ICON": icon]).image(size: 32))
        #expect(image.value(column: 31, row: 31) == 0xFF00_0000)
    }

    @Test func colorIcons() throws {
        // A 2×2 'cicn', 8 bits a pixel: its table red and blue, its mask the
        // left column.
        var writer = BigEndianWriter()
        writer.writeZeros(4)
        writer.write(UInt16(0x8000 | 2))                        // rowBytes
        for value: Int16 in [0, 0, 2, 2] { writer.write(UInt16(bitPattern: value)) }
        writer.writeZeros(2 + 2 + 4 + 4 + 4 + 2)
        writer.write(UInt16(8))                                 // pixelSize
        writer.writeZeros(2 + 2 + 4 + 4 + 4)
        for _ in 0 ..< 2 {                                       // maskBMap, iconBMap
            writer.writeZeros(4)
            writer.write(UInt16(2))
            for value: Int16 in [0, 0, 2, 2] { writer.write(UInt16(bitPattern: value)) }
        }
        writer.writeZeros(4)                                    // iconData
        writer.write(bytes: [0x80, 0, 0x80, 0])                 // mask
        writer.write(bytes: [0, 0, 0, 0])                       // 1-bit image
        writer.write(bytes: ColorTable(colors: [RGBColor(red8: 0xFF, green8: 0, blue8: 0), RGBColor(red8: 0, green8: 0, blue8: 0xFF)]).clut)
        writer.write(bytes: [0, 1, 1, 0])                       // pixels
        let icon = try ColorIcon(cicn: writer.bytes)
        #expect(icon.image == [0xFFFF_0000, 0x0000_00FF, 0xFF00_00FF, 0x00FF_0000])
        #expect(icon.pixels.value(column: 0, row: 1) == 0xFF00_00FF)
        #expect(throws: MacError.self) { try ColorIcon(cicn: Array(writer.bytes.prefix(60))) }
    }
}

@Suite struct CursorTests {

    @Test func cursRoundTrip() throws {
        let bytes = Cursor.arrow.curs
        #expect(bytes.count == 68)
        #expect(try Cursor(curs: bytes) == Cursor.arrow)
        #expect(throws: MacError.parameter) { try Cursor(curs: [1, 2, 3]) }
    }

    @Test func pixels() {
        let arrow = Cursor.arrow
        #expect(arrow.hotSpot == Point(v: 1, h: 1))
        #expect(arrow.pixel(row: 1, column: 1) == .black)
        #expect(arrow.pixel(row: 1, column: 0) == .white)
        #expect(arrow.pixel(row: 0, column: 5) == .transparent)
        let inverted = Cursor(data: [0x8000], mask: [0], hotSpot: .zero)
        #expect(inverted.pixel(row: 0, column: 0) == .inverted)
        #expect(arrow.argb.count == 256)
        #expect(arrow.argb[16 + 1] == 0xFF00_0000)
        #expect(arrow.argb[16] == 0xFFFF_FFFF)
        #expect(arrow.argb[5] == 0)
    }

    @Test func colorCursors() throws {
        // A 'crsr': its CCrsr record (96 bytes), a pixel map (50), its 2×2
        // pixels, 8 bits each, and their color table.
        var writer = BigEndianWriter()
        writer.write(UInt16(0x8001))
        writer.write(UInt32(96))                                // crsrMap
        writer.write(UInt32(146))                               // crsrData
        writer.writeZeros(4 + 2 + 4)
        for row in 0 ..< 16 { writer.write(UInt16(row < 2 ? 0xC000 : 0)) }   // data
        for row in 0 ..< 16 { writer.write(UInt16(row < 2 ? 0xC000 : 0)) }   // mask
        writer.write(UInt16(0))
        writer.write(UInt16(1))                                 // hot spot (0, 1)
        writer.writeZeros(8)
        #expect(writer.count == 96)
        writer.writeZeros(4)
        writer.write(UInt16(0x8000 | 2))
        for value: Int16 in [0, 0, 2, 2] { writer.write(UInt16(bitPattern: value)) }
        writer.writeZeros(2 + 2 + 4 + 4 + 4 + 2)
        writer.write(UInt16(8))
        writer.writeZeros(2 + 2 + 4)
        writer.write(UInt32(150))                               // pmTable
        writer.writeZeros(4)
        #expect(writer.count == 146)
        writer.write(bytes: [1, 0, 0, 1])
        writer.write(bytes: ColorTable(colors: [.white, RGBColor(red8: 0, green8: 0xFF, blue8: 0)]).clut)
        let cursor = try Cursor(crsr: writer.bytes)
        #expect(cursor.hotSpot == Point(v: 0, h: 1))
        #expect(cursor.colorWidth == 2)
        #expect(cursor.argb == [0xFF00_FF00, 0xFFFF_FFFF, 0xFFFF_FFFF, 0xFF00_FF00])
        #expect(throws: MacError.self) { try Cursor(crsr: Array(writer.bytes.prefix(100))) }
    }
}
