import struct Foundation.Data
import Testing
import GraphiteBase
import GraphiteQuickDraw

@Suite struct ParserBytesTests {

    /// A version 2 picture with nothing in it but its end.
    private func emptyPicture(frame: Rect) -> [UInt8] {
        var writer = BigEndianWriter()
        writer.write(UInt16(0))
        for value in [frame.top, frame.left, frame.bottom, frame.right] { writer.write(UInt16(bitPattern: value)) }
        writer.write(UInt16(0x0011))
        writer.write(UInt16(0x02FF))
        writer.write(UInt16(0x0C00))
        writer.writeZeros(24)
        writer.write(UInt16(0x00FF))
        return writer.bytes
    }

    private let frame = Rect(top: 0, left: 0, bottom: 20, right: 30)

    @Test func picturesFromAnyBytes() throws {
        let bytes = emptyPicture(frame: frame)
        #expect(try Picture(bytes: bytes).frame == frame)
        #expect(try Picture(bytes: Data(bytes)).frame == frame)
        #expect(try Picture(bytes: Data([5, 5, 5] + bytes)[3...]).frame == frame)
        #expect(try bytes.withUnsafeBytes { try Picture(bytes: $0) }.version == 2)
    }

    @Test func pictureFilesSkipTheirHeader() throws {
        let file = [UInt8](repeating: 0, count: 512) + emptyPicture(frame: frame)
        #expect(try Picture(file: file).frame == frame)
        #expect(try Picture(file: Data(file)).frame == frame)
        // A slice of a bigger Data, which doesn't start at 0.
        #expect(try Picture(file: Data([1, 2, 3] + file + [4])[3 ..< 3 + file.count]).frame == frame)
        #expect(throws: MacError.parameter) { try Picture(file: Data(count: 512)) }
        #expect(throws: MacError.parameter) { try Picture(file: Data()) }
    }

    @Test func packBitsFromAnyBytes() throws {
        let original: [UInt8] = [1, 1, 1, 1, 2, 3, 4, 4, 4, 4, 4, 5]
        let packed = PackBits.pack(original)
        #expect(PackBits.pack(Data(original)) == packed)
        #expect(try PackBits.unpack(packed, count: original.count) == original)
        #expect(try PackBits.unpack(Data(packed), count: original.count) == original)
        #expect(try PackBits.unpack(Data([9, 9] + packed)[2...], count: original.count) == original)
        #expect(throws: MacError.parameter) { try PackBits.unpack(Data(packed.prefix(2)), count: original.count) }
    }

    @Test func regionAndPolygonRecords() throws {
        let region = Region(rect: Rect(top: 1, left: 2, bottom: 30, right: 40)).subtracting(Region(rect: Rect(top: 5, left: 6, bottom: 10, right: 12)))
        #expect(try Region(record: Data(region.record)) == region)
        #expect(try Region(record: Data([3, 3] + region.record)[2...]) == region)
        let polygon = Polygon(points: [Point(v: 0, h: 0), Point(v: 10, h: 0), Point(v: 10, h: 10)])
        #expect(try Polygon(record: Data(polygon.record)) == polygon)
        #expect(try Polygon(record: Data([3, 3] + polygon.record)[2...]) == polygon)
        #expect(throws: MacError.parameter) { try Polygon(record: Data([0, 2])) }
    }

    @Test func cursorsFromAnyBytes() throws {
        let cursor = Cursor.arrow
        #expect(try Cursor(curs: Data(cursor.curs)) == cursor)
        #expect(try Cursor(curs: Data([8, 8, 8] + cursor.curs)[3...]) == cursor)
        #expect(try cursor.curs.withUnsafeBytes { try Cursor(curs: $0) } == cursor)
        #expect(throws: MacError.parameter) { try Cursor(curs: Data(cursor.curs.prefix(60))) }
    }
}
