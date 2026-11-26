import Foundation
import Testing
import GraphiteBase

@Suite struct ContiguousBytesTests {

    private let bytes: [UInt8] = [0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06]

    @Test func arraysAndDataAndBuffersGiveTheSameBytes() {
        #expect(Array(copying: bytes) == bytes)
        #expect(Array(copying: Data(bytes)) == bytes)
        #expect(bytes.withUnsafeBytes { Array(copying: $0) } == bytes)
        #expect(Array(copying: ContiguousArray(bytes)) == bytes)
    }

    @Test func aSliceOfDataIsCopiedFromItsOwnStart() {
        // A slice keeps its parent's indices; its bytes are what count.
        let slice = Data(bytes)[2 ..< 6]
        #expect(slice.startIndex == 2)
        #expect(Array(copying: slice) == [0x01, 0x02, 0x03, 0x04])
        #expect(Array(copying: bytes[2 ..< 6]) == [0x01, 0x02, 0x03, 0x04])
    }

    @Test func emptyBytes() {
        #expect(Array(copying: Data()).isEmpty)
        #expect(Array(copying: [UInt8]()).isEmpty)
    }

    @Test func aMappedFileReadsLikeAnArray() throws {
        let path = "/tmp/graphite-contiguous-\(getpid())"
        try Data(bytes).write(to: URL(fileURLWithPath: path))
        defer { unlink(path) }
        let mapped = try Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped)
        #expect(Array(copying: mapped) == bytes)
    }

    @Test func readersTakeAnyBytes() throws {
        var fromData = BigEndianReader(Data(bytes), offset: 2)
        #expect(try fromData.read(UInt16.self) == 0x0102)
        var fromSlice = BigEndianReader(Data(bytes)[4 ..< 8])
        #expect(try fromSlice.read(UInt32.self) == 0x0304_0506)
        var fromArray = BigEndianReader(bytes)
        #expect(try fromArray.read(UInt32.self) == 0x0000_0102)
        #expect(throws: BigEndianReadError.self) { _ = try fromSlice.read(UInt8.self) }
    }
}
