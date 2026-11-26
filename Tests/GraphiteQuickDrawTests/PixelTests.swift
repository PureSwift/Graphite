import Testing
import GraphiteBase
import GraphiteQuickDraw

@Suite struct PixelTests {

    let rect = Rect(top: 10, left: 20, bottom: 14, right: 30)

    @Test(arguments: [1, 2, 4, 8, 16, 32])
    func valuesRoundTrip(depth: Int) throws {
        let format = try #require(PixelFormat(depth: depth))
        let buffer = PixelBuffer(bounds: rect, format: format)
        #expect(buffer.rowBytes % 4 == 0)
        #expect(buffer.rowBytes >= (10 * depth + 7) / 8)
        let maximum: UInt32 = depth == 32 ? 0xFFFF_FFFF : 1 << UInt32(depth) - 1
        for column in 0 ..< 10 {
            buffer.setValue(UInt32(column) * 7 & maximum, at: Point(v: 12, h: Int16(20 + column)))
        }
        for column in 0 ..< 10 {
            #expect(buffer.value(at: Point(v: 12, h: Int16(20 + column))) == UInt32(column) * 7 & maximum)
            // Neighbors untouched.
            #expect(buffer.value(at: Point(v: 11, h: Int16(20 + column))) == 0)
        }
        #expect(buffer.value(at: Point(v: 9, h: 20)) == nil)
    }

    @Test func indexedPixelsPackHighBitsFirst() {
        let buffer = PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: 1, right: 8), format: .indexed(depth: 1))
        buffer.setValue(1, at: Point(v: 0, h: 0))
        buffer.setValue(1, at: Point(v: 0, h: 7))
        #expect(buffer.bytes[0] == 0b1000_0001)
        let four = PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: 1, right: 2), format: .indexed(depth: 4))
        four.setValue(0xA, at: Point(v: 0, h: 0))
        four.setValue(0x5, at: Point(v: 0, h: 1))
        #expect(four.bytes[0] == 0xA5)
    }

    @Test func directPixelsAreBigEndian() {
        let buffer = PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: 1, right: 1), format: .argb32)
        buffer.setColor(RGBColor(red8: 0x12, green8: 0x34, blue8: 0x56), at: .zero)
        #expect(Array(buffer.bytes[0 ..< 4]) == [0xFF, 0x12, 0x34, 0x56])
        let sixteen = PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: 1, right: 1), format: .rgb555)
        sixteen.setColor(.white, at: .zero)
        #expect(Array(sixteen.bytes[0 ..< 2]) == [0x7F, 0xFF])
        #expect(sixteen.color(at: .zero) == .white)
    }

    @Test func colorsThroughTables() throws {
        let buffer = PixelBuffer(bounds: rect, format: .indexed(depth: 8))
        buffer.setColor(.black, at: Point(v: 10, h: 20))
        #expect(buffer.value(at: Point(v: 10, h: 20)) == 255)
        buffer.setColor(RGBColor(red8: 0xFF, green8: 0, blue8: 0), at: Point(v: 10, h: 21))
        #expect(buffer.color(at: Point(v: 10, h: 21)) == RGBColor(red8: 0xFF, green8: 0, blue8: 0))
        // A color the table hasn't: the nearest.
        buffer.setColor(RGBColor(red8: 0xFE, green8: 0x01, blue8: 0x02), at: Point(v: 10, h: 22))
        #expect(buffer.color(at: Point(v: 10, h: 22)) == RGBColor(red8: 0xFF, green8: 0, blue8: 0))
    }

    @Test func standardTables() throws {
        let eight = try #require(ColorTable.standard(depth: 8))
        #expect(eight.colors.count == 256)
        #expect(eight[0] == .white)
        #expect(eight[255] == .black)
        #expect(eight[215] == RGBColor(red8: 0xEE, green8: 0, blue8: 0))
        #expect(eight[254] == RGBColor(red8: 0x11, green8: 0x11, blue8: 0x11))
        #expect(Set(eight.colors).count == 256)
        #expect(ColorTable.standard(depth: 4)?.colors.count == 16)
        #expect(ColorTable.standard(depth: 1)?.colors == [.white, .black])
        #expect(ColorTable.standard(depth: 16) == nil)
    }

    @Test func clutResources() throws {
        let table = ColorTable(seed: 77, colors: [.white, RGBColor(red: 1, green: 2, blue: 3), .black])
        #expect(try ColorTable(clut: table.clut) == table)
        #expect(throws: MacError.mapRead) { try ColorTable(clut: [0, 0, 0]) }
    }

    @Test func fillsAreClipped() {
        let buffer = PixelBuffer(bounds: rect, format: .argb32)
        buffer.fill(Rect(top: 0, left: 0, bottom: 11, right: 22), with: 0xFF00_00FF)
        #expect(buffer.value(at: Point(v: 10, h: 21)) == 0xFF00_00FF)
        #expect(buffer.value(at: Point(v: 10, h: 22)) == 0)
        #expect(buffer.value(at: Point(v: 11, h: 20)) == 0)
    }

    @Test func wrappedMemory() {
        var memory = [UInt8](repeating: 0, count: 16)
        memory.withUnsafeMutableBytes { raw in
            let buffer = PixelBuffer(wrapping: raw.baseAddress!, rowBytes: 8, bounds: Rect(top: 0, left: 0, bottom: 2, right: 2), format: .argb32)
            buffer.setValue(0x0102_0304, at: Point(v: 1, h: 1))
        }
        #expect(Array(memory[12 ..< 16]) == [1, 2, 3, 4])
    }
}
