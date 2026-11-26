import Testing
import GraphiteBase
import GraphiteQuickDraw

/// Builds a version 2 picture's bytes: header, opcodes, end.
private struct PictureWriter {
    var writer = BigEndianWriter()

    init(frame: Rect) {
        writer.write(UInt16(0))
        for value in [frame.top, frame.left, frame.bottom, frame.right] { writer.write(UInt16(bitPattern: value)) }
        writer.write(UInt16(0x0011))
        writer.write(UInt16(0x02FF))
        writer.write(UInt16(0x0C00))
        writer.writeZeros(24)
    }

    mutating func opcode(_ value: UInt16) {
        if writer.count % 2 == 1 { writer.write(UInt8(0)) }
        writer.write(value)
    }

    mutating func rect(_ rect: Rect) {
        for value in [rect.top, rect.left, rect.bottom, rect.right] { writer.write(UInt16(bitPattern: value)) }
    }

    mutating func color(_ color: RGBColor) {
        writer.write(color.red)
        writer.write(color.green)
        writer.write(color.blue)
    }

    mutating func end() -> [UInt8] {
        opcode(0x00FF)
        return writer.bytes
    }
}

@Suite struct PictureTests {

    let red = RGBColor(red8: 0xFF, green8: 0, blue8: 0)
    let frame = Rect(top: 0, left: 0, bottom: 8, right: 8)

    private func world(_ rect: Rect, depth: Int = 32) throws -> GraphicsWorld {
        let world = try GraphicsWorld(bounds: rect, depth: depth)
        world.port.eraseAll()
        return world
    }

    @Test func packBits() throws {
        // Apple's example (Technical Note TN1023).
        let unpacked: [UInt8] = [0xAA, 0xAA, 0xAA, 0x80, 0x00, 0x2A, 0xAA, 0xAA, 0xAA, 0xAA, 0x80, 0x00, 0x2A, 0x22,
                                 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA]
        let packed: [UInt8] = [0xFE, 0xAA, 0x02, 0x80, 0x00, 0x2A, 0xFD, 0xAA, 0x03, 0x80, 0x00, 0x2A, 0x22, 0xF7, 0xAA]
        #expect(try PackBits.unpack(packed, count: unpacked.count) == unpacked)
        #expect(PackBits.pack(unpacked) == packed)
        let long = (0 ..< 300).map { UInt8(truncatingIfNeeded: $0 * 7 / 3) }
        #expect(try PackBits.unpack(PackBits.pack(long), count: long.count) == long)
        // Two bytes a unit, as 16-bit pixels are packed.
        #expect(try PackBits.unpack([0xFE, 0x12, 0x34], count: 6, unit: 2) == [0x12, 0x34, 0x12, 0x34, 0x12, 0x34])
        #expect(throws: MacError.parameter) { try PackBits.unpack([0x05, 0x01], count: 6) }
    }

    @Test func versionTwoShapesAndColors() throws {
        var picture = PictureWriter(frame: frame)
        picture.opcode(0x001A)
        picture.color(red)
        picture.opcode(0x0031)                                   // PaintRect
        picture.rect(Rect(top: 2, left: 2, bottom: 4, right: 4))
        let parsed = try Picture(bytes: picture.end())
        #expect(parsed.version == 2)
        #expect(parsed.frame == frame)
        #expect(parsed.operations.count == 2)
        let world = try world(frame)
        parsed.draw(in: world.port, destination: frame)
        #expect(world.pixels.color(at: Point(v: 3, h: 3)) == red)
        #expect(world.pixels.color(at: Point(v: 5, h: 5)) == .white)
        // The port's state is its own again after.
        #expect(world.port.foreColor == .black)
    }

    @Test func versionOne() throws {
        var writer = BigEndianWriter()
        writer.write(UInt16(0))
        for value: Int16 in [0, 0, 8, 12] { writer.write(UInt16(bitPattern: value)) }
        writer.write(bytes: [0x11, 0x01])                        // version 1
        writer.write(UInt8(0x50))                                // FrameOval
        for value: Int16 in [0, 0, 8, 12] { writer.write(UInt16(bitPattern: value)) }
        writer.write(UInt8(0xFF))
        let picture = try Picture(bytes: writer.bytes)
        #expect(picture.version == 1)
        let drawn = bitmapPort(width: 12, height: 8)
        picture.draw(in: drawn, destination: drawn.portRect)
        let expected = bitmapPort(width: 12, height: 8)
        expected.perform(.frame, oval: expected.portRect)
        #expect(snapshot(drawn) == snapshot(expected))
    }

    @Test func linesAndScaling() throws {
        var picture = PictureWriter(frame: frame)
        picture.opcode(0x0020)                                   // Line
        for value: Int16 in [0, 0, 0, 7] { picture.writer.write(UInt16(bitPattern: value)) }
        picture.opcode(0x0023)                                   // ShortLineFrom: down 7
        picture.writer.write(UInt8(0))
        picture.writer.write(UInt8(7))
        let parsed = try Picture(bytes: picture.end())
        let port = bitmapPort(width: 8, height: 8)
        parsed.draw(in: port, destination: port.portRect)
        #expect(port.pixels?.color(at: Point(v: 0, h: 4)) == .black)
        #expect(port.pixels?.color(at: Point(v: 7, h: 7)) == .black)
        // Twice the size.
        var square = PictureWriter(frame: frame)
        square.opcode(0x0031)
        square.rect(Rect(top: 0, left: 0, bottom: 4, right: 4))
        let scaled = bitmapPort(width: 16, height: 16)
        try Picture(bytes: square.end()).draw(in: scaled, destination: scaled.portRect)
        #expect(scaled.pixels?.color(at: Point(v: 7, h: 7)) == .black)
        #expect(scaled.pixels?.color(at: Point(v: 8, h: 8)) == .white)
    }

    @Test func packedBitmaps() throws {
        // An 8×2 bitmap: its rows are under 8 bytes, so they aren't packed.
        var picture = PictureWriter(frame: frame)
        picture.opcode(0x0090)                                   // BitsRect
        picture.writer.write(UInt16(2))                          // rowBytes
        picture.rect(Rect(top: 0, left: 0, bottom: 2, right: 8))
        picture.rect(Rect(top: 0, left: 0, bottom: 2, right: 8))
        picture.rect(Rect(top: 0, left: 0, bottom: 2, right: 8))
        picture.writer.write(UInt16(0))                          // srcCopy
        picture.writer.write(bytes: [0xF0, 0x00, 0x0F, 0x00])    // the rows
        let parsed = try Picture(bytes: picture.end())
        let port = bitmapPort(width: 8, height: 2)
        parsed.draw(in: port, destination: Rect(top: 0, left: 0, bottom: 8, right: 8))
        #expect(snapshot(port) == """
        ####....
        ....####
        """)
    }

    @Test func packedPixelMapsWithColorTables() throws {
        // A 16×1 pixel map, 8 bits a pixel, its color table two colors, its
        // row of 16 bytes packed.
        var picture = PictureWriter(frame: Rect(top: 0, left: 0, bottom: 1, right: 16))
        picture.opcode(0x0098)                                   // PackBitsRect
        picture.writer.write(UInt16(0x8000 | 16))
        picture.rect(Rect(top: 0, left: 0, bottom: 1, right: 16))
        picture.writer.write(UInt16(0))                          // pmVersion
        picture.writer.write(UInt16(0))                          // packType
        picture.writer.writeZeros(12)                            // packSize, hRes, vRes
        picture.writer.write(UInt16(0))                          // pixelType
        picture.writer.write(UInt16(8))                          // pixelSize
        picture.writer.write(UInt16(1))                          // cmpCount
        picture.writer.write(UInt16(8))                          // cmpSize
        picture.writer.writeZeros(12)                            // planeBytes, pmTable, pmReserved
        picture.writer.write(bytes: ColorTable(colors: [.white, red]).clut)
        picture.rect(Rect(top: 0, left: 0, bottom: 1, right: 16))
        picture.rect(Rect(top: 0, left: 0, bottom: 1, right: 16))
        picture.writer.write(UInt16(0))
        let row = PackBits.pack([UInt8](repeating: 1, count: 8) + [UInt8](repeating: 0, count: 8))
        picture.writer.write(UInt8(row.count))
        picture.writer.write(bytes: row)
        let parsed = try Picture(bytes: picture.end())
        let world = try world(Rect(top: 0, left: 0, bottom: 1, right: 16))
        parsed.draw(in: world.port, destination: world.port.portRect)
        #expect(world.pixels.color(at: Point(v: 0, h: 3)) == red)
        #expect(world.pixels.color(at: Point(v: 0, h: 12)) == .white)
    }

    @Test func directPixelsInPlanes() throws {
        // A 8×1 pixel map, 32 bits a pixel, packed as three planes.
        var picture = PictureWriter(frame: Rect(top: 0, left: 0, bottom: 1, right: 8))
        picture.opcode(0x009A)                                   // DirectBitsRect
        picture.writer.write(UInt32(0xFF))                       // baseAddr
        picture.writer.write(UInt16(0x8000 | 32))
        picture.rect(Rect(top: 0, left: 0, bottom: 1, right: 8))
        picture.writer.write(UInt16(0))
        picture.writer.write(UInt16(4))                          // packType: planes
        picture.writer.writeZeros(12)
        picture.writer.write(UInt16(16))                         // RGBDirect
        picture.writer.write(UInt16(32))
        picture.writer.write(UInt16(3))
        picture.writer.write(UInt16(8))
        picture.writer.writeZeros(12)
        picture.rect(Rect(top: 0, left: 0, bottom: 1, right: 8))
        picture.rect(Rect(top: 0, left: 0, bottom: 1, right: 8))
        picture.writer.write(UInt16(0))
        let planes = [UInt8](repeating: 0xFF, count: 8) + [UInt8](repeating: 0, count: 16)   // red, green, blue
        let row = PackBits.pack(planes)
        picture.writer.write(UInt8(row.count))
        picture.writer.write(bytes: row)
        let parsed = try Picture(bytes: picture.end())
        let world = try world(Rect(top: 0, left: 0, bottom: 1, right: 8))
        parsed.draw(in: world.port, destination: world.port.portRect)
        #expect(world.pixels.color(at: Point(v: 0, h: 5)) == red)
    }

    @Test func opcodesItDoesntUseAreSkipped() throws {
        var picture = PictureWriter(frame: frame)
        picture.opcode(0x00A5)                                   // reserved: a word's length
        picture.writer.write(UInt16(3))
        picture.writer.write(bytes: [1, 2, 3])
        picture.opcode(0x0200)                                   // reserved: (0x02 × 2) bytes
        picture.writer.writeZeros(4)
        picture.opcode(0x8100)                                   // reserved: a long's length
        picture.writer.write(UInt32(2))
        picture.writer.writeZeros(2)
        picture.opcode(0x00A1)                                   // LongComment
        picture.writer.write(UInt16(100))
        picture.writer.write(UInt16(2))
        picture.writer.write(bytes: [9, 9])
        picture.opcode(0x0028)                                   // LongText
        picture.writer.write(UInt16(5))
        picture.writer.write(UInt16(6))
        picture.writer.write(bytes: PascalString("Hi").lengthPrefixed)
        picture.opcode(0x0031)
        picture.rect(frame)
        let parsed = try Picture(bytes: picture.end())
        let port = bitmapPort(width: 8, height: 8)
        parsed.draw(in: port, destination: port.portRect)
        #expect(port.pixels?.color(at: Point(v: 4, h: 4)) == .black)
        let kinds = parsed.operations.compactMap { operation -> String? in
            switch operation {
            case .comment(let kind, let data): return "comment \(kind) \(data)"
            case .text(let text, let location): return "text \(text.string) \(location.v),\(location.h)"
            default: return nil
            }
        }
        #expect(kinds == ["comment 100 [9, 9]", "text Hi 5,6"])
    }

    @Test func compressedImagesGoToTheDecoder() throws {
        final class Decoder: PictureImageDecoder {
            var asked: (FourCharCode, Int, Int)?
            func decode(codec: FourCharCode, width: Int, height: Int, depth: Int, data: [UInt8]) -> PixelBuffer? {
                asked = (codec, width, height)
                let buffer = PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: Int16(height), right: Int16(width)), format: .argb32)
                buffer.fill(buffer.bounds, with: 0xFFFF_0000)
                return buffer
            }
        }
        var picture = PictureWriter(frame: frame)
        picture.opcode(0x8200)
        var body = BigEndianWriter()
        body.write(UInt16(0))                                    // version
        for value: UInt32 in [0x10000, 0, 0, 0, 0x10000, 0, 0x20000, 0x10000, 0x4000_0000] { body.write(value) }   // translate (2, 1)
        body.write(UInt32(0))                                    // matteSize
        body.writeZeros(8)
        body.write(UInt16(0))                                    // srcCopy
        for value: Int16 in [0, 0, 2, 2] { body.write(UInt16(bitPattern: value)) }
        body.write(UInt32(0))                                    // accuracy
        body.write(UInt32(0))                                    // maskSize
        var description = BigEndianWriter()
        description.write(UInt32(86))
        description.write(FourCharCode("jpeg").rawValue)
        description.writeZeros(24)
        description.write(UInt16(2))
        description.write(UInt16(2))
        description.writeZeros(8)
        description.write(UInt32(3))                             // dataSize
        description.writeZeros(34)
        description.write(UInt16(24))
        description.write(UInt16(0xFFFF))
        body.write(bytes: description.bytes)
        body.write(bytes: [1, 2, 3])
        picture.writer.write(UInt32(body.count))
        picture.writer.write(bytes: body.bytes)
        let parsed = try Picture(bytes: picture.end())
        let decoder = Decoder()
        let world = try world(frame)
        parsed.draw(in: world.port, destination: frame, decoder: decoder)
        #expect(decoder.asked?.0 == "jpeg")
        #expect(decoder.asked?.1 == 2)
        #expect(world.pixels.color(at: Point(v: 1, h: 2)) == red)
        #expect(world.pixels.color(at: Point(v: 0, h: 0)) == .white)
        // Without a decoder, nothing is drawn.
        let other = try self.world(frame)
        parsed.draw(in: other.port, destination: frame)
        #expect(other.pixels.color(at: Point(v: 1, h: 2)) == .white)
    }

    @Test func malformedPicturesThrow() throws {
        var picture = PictureWriter(frame: frame)
        picture.opcode(0x001A)
        picture.color(red)
        picture.opcode(0x0031)
        picture.rect(frame)
        let bytes = picture.end()
        for length in 0 ..< bytes.count {
            #expect(throws: MacError.self) { try Picture(bytes: Array(bytes.prefix(length))) }
        }
        #expect(throws: MacError.parameter) { try Picture(bytes: [0, 0, 0, 0, 0, 0, 0, 8, 0, 8, 0x12, 0x34]) }
        // A PICT file's 512-byte header.
        #expect(try Picture(file: [UInt8](repeating: 0, count: 512) + bytes).operations.count == 2)
    }
}
