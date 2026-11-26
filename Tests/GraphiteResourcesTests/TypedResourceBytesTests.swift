import struct Foundation.Data
import Testing
import GraphiteBase
import GraphiteFiles
import GraphiteResources

@Suite struct TypedResourceBytesTests {

    @Test func stringLists() throws {
        let bytes: [UInt8] = [0, 2, 3, 0x61, 0x62, 0x63, 1, 0x78]
        let expected = StringList(strings: [PascalString(bytes: [0x61, 0x62, 0x63]), PascalString(bytes: [0x78])])
        #expect(try StringList(bytes: bytes) == expected)
        #expect(try StringList(bytes: Data(bytes)) == expected)
        #expect(try StringList(bytes: Data([1, 1] + bytes)[2...]) == expected)
        #expect(try bytes.withUnsafeBytes { try StringList(bytes: $0) } == expected)
        #expect(throws: MacError.mapRead) { try StringList(bytes: Data([0, 3, 1, 0x61])) }
    }

    @Test func stringResources() {
        let bytes: [UInt8] = [3, 0x61, 0x62, 0x63]
        let expected = StringResource(string: PascalString(bytes: [0x61, 0x62, 0x63]))
        #expect(StringResource(bytes: bytes) == expected)
        #expect(StringResource(bytes: Data(bytes)) == expected)
        #expect(StringResource(bytes: Data([7] + bytes)[1...]) == expected)
    }

    @Test func versions() throws {
        let bytes: [UInt8] = [1, 0x23, 0x80, 0, 0, 0, 3, 0x31, 0x2E, 0x30, 2, 0x4F, 0x4B]
        let fromArray = try VersionResource(bytes: bytes)
        #expect(fromArray.major == 1)
        #expect(fromArray.shortVersion == PascalString(bytes: Array("1.0".utf8)))
        #expect(fromArray.longVersion == PascalString(bytes: Array("OK".utf8)))
        #expect(try VersionResource(bytes: Data(bytes)) == fromArray)
        #expect(try VersionResource(bytes: Data([5, 5] + bytes)[2...]) == fromArray)
        #expect(throws: MacError.mapRead) { try VersionResource(bytes: Data(bytes.prefix(8))) }
    }

    @Test func openingAChainFileFromData() throws {
        let fork = try ResourceMap.write([(Resource(type: "TEXT", id: 128), [1, 2, 3])])
        let folder = TemporaryFolder()
        let chain = ResourceChain(fileSystem: FileSystem(defaultFolder: folder.path))
        let fromData = try chain.open(bytes: Data(fork))
        let fromSlice = try chain.open(bytes: Data([4, 4, 4] + fork)[3...])
        #expect(fromData != fromSlice)
        #expect(try chain.get(type: "TEXT", id: 128).bytes == [1, 2, 3])
    }
}
