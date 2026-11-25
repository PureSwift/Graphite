import Testing
import GraphiteBase

@Suite struct BigEndianTests {

    @Test func integers() throws {
        var reader = BigEndianReader([0x01, 0x02, 0x03, 0x04, 0xFF, 0xFE, 0x80])
        let value1 = try reader.read(UInt16.self)
        #expect(value1 == 0x0102)
        let value2 = try reader.read(UInt16.self)
        #expect(value2 == 0x0304)
        let value3 = try reader.read(Int16.self)
        #expect(value3 == -2)
        let value4 = try reader.read(Int8.self)
        #expect(value4 == -128)
        #expect(reader.isAtEnd)
        let value5 = try reader.peek(UInt32.self, at: 0)
        #expect(value5 == 0x0102_0304)
    }

    @Test func readsPastTheEndThrow() {
        var reader = BigEndianReader([0x01, 0x02, 0x03])
        #expect(throws: BigEndianReadError(offset: 0, count: 4, available: 3)) { try reader.read(UInt32.self) }
        #expect(reader.offset == 0)
        #expect(throws: BigEndianReadError.self) { try reader.readBytes(-1) }
        #expect(throws: BigEndianReadError.self) { try reader.seek(to: 4) }
        #expect(throws: BigEndianReadError.self) { try reader.peek(UInt8.self, at: -1) }
        #expect(throws: BigEndianReadError.self) { try reader.readBytes(.max) }
        #expect(throws: BigEndianReadError.self) { try reader.subreader(at: 2, count: 2) }
    }

    @Test func pascalStringsPastTheEndThrow() {
        var reader = BigEndianReader([5, 0x41, 0x42])
        #expect(throws: BigEndianReadError.self) { try reader.readPascalString() }
    }

    @Test func toolboxTypesRoundTrip() throws {
        var writer = BigEndianWriter()
        writer.write(FourCharCode("STR#"))
        writer.write(PascalString("Hello"))
        writer.write(PascalString("Hi"), capacity: 31)
        writer.write(Point(v: -1, h: 2))
        writer.write(Rect(top: 1, left: 2, bottom: 3, right: 4))
        writer.write(Fixed(1.5))
        writer.write(Extended80(44100))
        writer.write(true)
        writer.write(UInt64(0x0102_0304_0506_0708))

        #expect(writer.count == 4 + 6 + 32 + 4 + 8 + 4 + 10 + 1 + 8)
        var reader = BigEndianReader(writer.bytes)
        let value6 = try reader.readFourCharCode()
        #expect(value6 == "STR#")
        let value7 = try reader.readPascalString()
        #expect(value7 == "Hello")
        let value8 = try reader.readPascalString(capacity: 31)
        #expect(value8 == "Hi")
        let value9 = try reader.readPoint()
        #expect(value9 == Point(v: -1, h: 2))
        let value10 = try reader.readRect()
        #expect(value10 == Rect(top: 1, left: 2, bottom: 3, right: 4))
        let value11 = try reader.readFixed()
        #expect(value11 == Fixed(1.5))
        let value12 = try reader.readExtended80().doubleValue
        #expect(value12 == 44100)
        let value13 = try reader.readBool()
        #expect(value13)
        let value14 = try reader.read(UInt64.self)
        #expect(value14 == 0x0102_0304_0506_0708)
        #expect(reader.isAtEnd)
    }

    @Test func fixedFieldsCutLongStrings() throws {
        var writer = BigEndianWriter()
        writer.write(PascalString("abcdef"), capacity: 3)
        #expect(writer.bytes == [3, 0x61, 0x62, 0x63])
    }

    @Test func backPatchingAndAlignment() {
        var writer = BigEndianWriter()
        writer.write(UInt32(0))
        writer.write(UInt8(7))
        writer.align(to: 4)
        #expect(writer.count == 8)
        let patched = writer.set(UInt32(0xDEAD_BEEF), at: 0)
        let pastTheEnd = writer.set(UInt32(1), at: 6)
        let beforeTheStart = writer.set(UInt16(1), at: -1)
        #expect(patched && !pastTheEnd && !beforeTheStart)
        #expect(writer.bytes == [0xDE, 0xAD, 0xBE, 0xEF, 7, 0, 0, 0])
    }

    @Test func subreadersAndSeeking() throws {
        var reader = BigEndianReader([0, 1, 2, 3, 4, 5, 6, 7])
        try reader.skip(1)
        reader.align(to: 4)
        #expect(reader.offset == 4)
        var sub = try reader.subreader(2)
        let value15 = try sub.read(UInt16.self)
        #expect(value15 == 0x0405)
        #expect(reader.offset == 6)
        #expect(reader.remaining == 2)
        try reader.seek(to: 8)
        #expect(reader.isAtEnd)
        reader.align(to: 16)
        #expect(reader.offset == 8)
        let other = try reader.subreader(at: 1, count: 3)
        #expect(other.bytes == [1, 2, 3])
    }

    @Test func randomBytesNeverTrap() {
        var generator = QuickDrawRandom(seed: 42)
        for _ in 0 ..< 500 {
            let count = Int(UInt16(bitPattern: generator.next()) % 32)
            let bytes = (0 ..< count).map { _ in UInt8(truncatingIfNeeded: generator.next()) }
            var reader = BigEndianReader(bytes)
            while true {
                do {
                    let length = try reader.read(UInt8.self)
                    _ = try reader.readBytes(Int(length) % 8)
                    _ = try reader.readPascalString()
                    _ = try reader.readRect()
                } catch {
                    break
                }
            }
        }
    }
}
