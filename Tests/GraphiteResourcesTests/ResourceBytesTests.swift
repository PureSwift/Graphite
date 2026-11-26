import struct Foundation.Data
import Testing
import GraphiteBase
import GraphiteFiles
import GraphiteResources

@Suite struct ResourceBytesTests {

    private let resources: [(resource: Resource, bytes: [UInt8])] = [
        (Resource(type: "TEXT", id: 128, name: "First"), Array("hello".utf8)),
        (Resource(type: "TEXT", id: 129), [1, 2, 3]),
        (Resource(type: "ICN#", id: -16455), [UInt8](repeating: 0xFF, count: 256)),
    ]

    private func fork() throws -> [UInt8] {
        try ResourceMap.write(resources)
    }

    @Test func mapsReadFromAnyBytes() throws {
        let bytes = try fork()
        let fromArray = try ResourceMap(parsing: bytes)
        #expect(fromArray.entries.count == 3)
        #expect(try ResourceMap(parsing: Data(bytes)) == fromArray)
        #expect(try bytes.withUnsafeBytes { try ResourceMap(parsing: $0) } == fromArray)
    }

    @Test func aSliceOfDataIsAFork() throws {
        let bytes = try fork()
        let padded = Data([7, 7, 7, 7, 7] + bytes + [9, 9, 9])
        let slice = padded[5 ..< 5 + bytes.count]
        #expect(slice.startIndex == 5)
        #expect(try ResourceMap(parsing: slice) == ResourceMap(parsing: bytes))
        let file = try ResourceFile(bytes: slice)
        #expect(try file.bytes(type: "TEXT", id: 128) == Array("hello".utf8))
        #expect(try file.bytes(type: "TEXT", id: 129) == [1, 2, 3])
        #expect(try file.bytes(type: "ICN#", id: -16455).count == 256)
    }

    @Test func filesReadFromAnyBytes() throws {
        let bytes = try fork()
        for file in [try ResourceFile(bytes: bytes), try ResourceFile(bytes: Data(bytes))] {
            #expect(file.types == ["TEXT", "ICN#"])
            #expect(try file.bytes(type: "TEXT", id: 129) == [1, 2, 3])
        }
    }

    @Test func truncatedSlicesNeverTrap() throws {
        let bytes = try fork()
        let padded = Data([1, 2, 3] + bytes)
        for length in 0 ... bytes.count {
            _ = try? ResourceMap(parsing: padded[3 ..< 3 + length])
            _ = try? ResourceFile(bytes: padded[3 ..< 3 + length])
        }
    }

    @Test func aResourceFileInADataForkIsReadFromTheFork() throws {
        let folder = TemporaryFolder()
        folder.write("Data.rsrc", try fork())
        let file = try ResourceFile(fork: Fork(path: folder.path("Data.rsrc"), kind: .data, permission: .read))
        #expect(file.attributes.contains(.readOnly))
        #expect(file.resources.count == 3)
        #expect(try file.bytes(type: "TEXT", id: 128) == Array("hello".utf8))
        #expect(try file.size(type: "ICN#", id: -16455) == 256)
    }

    @Test func updatingWritesBackAndReadsAgain() throws {
        let folder = TemporaryFolder()
        folder.write("Data.rsrc", try fork())
        let file = try ResourceFile(fork: Fork(path: folder.path("Data.rsrc"), kind: .data, permission: .readWrite))
        try file.setBytes([9, 9], type: "TEXT", id: 129)
        try file.add(Resource(type: "STR ", id: 128), bytes: [3, 0x61, 0x62, 0x63])
        try file.update()
        #expect(try file.bytes(type: "TEXT", id: 129) == [9, 9])
        #expect(try file.bytes(type: "STR ", id: 128) == [3, 0x61, 0x62, 0x63])
        #expect(try file.bytes(type: "TEXT", id: 128) == Array("hello".utf8))
        // What is on disk reads the same.
        let again = try ResourceFile(bytes: try #require(folder.read("Data.rsrc")))
        #expect(try again.bytes(type: "TEXT", id: 129) == [9, 9])
        #expect(again.resources.count == 4)
    }
}
