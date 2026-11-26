import Foundation
import Testing
import GraphiteBase
import GraphiteFiles
import GraphiteResources

@Suite struct ForkContentsTests {

    private let bytes = (0 ..< 5000).map { UInt8(truncatingIfNeeded: $0 &* 7) }

    @Test func readsTheWholeDataFork() throws {
        let folder = TemporaryFolder()
        folder.write("data", bytes)
        let fork = try Fork(path: folder.path("data"), kind: .data, permission: .read)
        #expect(Array(try fork.contents()) == bytes)
        // Whatever the mark was.
        _ = try fork.seek(.start(100))
        #expect(Array(try fork.contents()) == bytes)
    }

    @Test func aForkOpenForWritingIsReadIntoMemory() throws {
        let folder = TemporaryFolder()
        folder.write("data", bytes)
        let fork = try Fork(path: folder.path("data"), kind: .data, permission: .readWrite)
        let contents = try fork.contents()
        #expect(Array(contents) == bytes)
        // A copy: the file changing afterwards doesn't show in it.
        folder.write("data", [UInt8](repeating: 0, count: bytes.count))
        #expect(Array(contents) == bytes)
    }

    @Test func aResourceForkIsReadIntoMemory() throws {
        let folder = TemporaryFolder()
        folder.write("file", [])
        var double = AppleDouble()
        double.resourceFork = bytes
        folder.write("._file", double.bytes)
        let fork = try Fork(path: folder.path("file"), kind: .resource, permission: .read)
        #expect(Array(try fork.contents()) == bytes)
    }

    @Test func contentsStartAtZeroWhateverTheStorage() throws {
        let folder = TemporaryFolder()
        folder.write("data", bytes)
        let contents = try Fork(path: folder.path("data"), kind: .data, permission: .read).contents()
        #expect(contents.startIndex == 0)
        #expect(contents.count == bytes.count)
    }

    @Test func anEmptyForkIsEmpty() throws {
        let folder = TemporaryFolder()
        folder.write("empty", [])
        let fork = try Fork(path: folder.path("empty"), kind: .data, permission: .read)
        #expect(try fork.contents().isEmpty)
    }
}
