import Testing
import GraphiteBase
import GraphiteFiles
import GraphiteResources

@Suite struct ForkContentsTests {

    @Test func readsTheWholeDataFork() throws {
        let folder = TemporaryFolder()
        let bytes = (0 ..< 5000).map { UInt8(truncatingIfNeeded: $0 &* 7) }
        folder.write("data", bytes)
        let fork = try Fork(path: folder.path("data"), kind: .data, permission: .read)
        #expect(try fork.contents() == bytes)
        // Whatever the mark was.
        _ = try fork.seek(.start(100))
        #expect(try fork.contents() == bytes)
    }

    @Test func anEmptyForkIsEmpty() throws {
        let folder = TemporaryFolder()
        folder.write("empty", [])
        let fork = try Fork(path: folder.path("empty"), kind: .data, permission: .read)
        #expect(try fork.contents().isEmpty)
    }
}
