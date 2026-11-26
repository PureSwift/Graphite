import Testing
import GraphiteBase
import GraphiteFiles

@Suite struct ForkTests {

    private func read(_ fork: Fork, _ count: Int, from position: ForkPosition? = nil) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: count)
        let got = try buffer.withUnsafeMutableBytes { try fork.read(into: $0, from: position) }
        return Array(buffer[0 ..< got])
    }

    private func write(_ fork: Fork, _ bytes: [UInt8], at position: ForkPosition? = nil) throws {
        try bytes.withUnsafeBytes { _ = try fork.write($0, at: position) }
    }

    @Test func dataForks() throws {
        let folder = TemporaryFolder()
        folder.write("File", Array(0 ..< 10))
        let files = FileSystem(defaultFolder: folder.path)
        let (reference, fork) = try files.open(folder.path("File"), fork: .data, permission: .readWrite)
        #expect(reference >= 2)
        #expect(files.fork(reference) === fork)
        #expect(fork.size == 10)
        #expect(try read(fork, 4) == [0, 1, 2, 3])
        #expect(fork.position == 4)
        #expect(try read(fork, 2, from: .end(-2)) == [8, 9])
        // Past the end: what there is.
        #expect(try read(fork, 4, from: .start(8)) == [8, 9])
        try write(fork, [0xAA, 0xBB], at: .start(10))
        #expect(fork.size == 12)
        try fork.setSize(5)
        #expect(fork.size == 5)
        #expect(throws: MacError.position) { try fork.seek(.start(-1)) }
        try files.close(reference)
        #expect(files.fork(reference) == nil)
        #expect(throws: MacError.referenceNumber) { try files.close(reference) }
        #expect(folder.read("File") == [0, 1, 2, 3, 4])
    }

    @Test func readOnlyForksDontWrite() throws {
        let folder = TemporaryFolder()
        folder.write("File", [1])
        let fork = try Fork(path: folder.path("File"), kind: .data, permission: .read)
        #expect(throws: MacError.writePermission) { try write(fork, [2]) }
    }

    @Test func missingFilesHaveNoForks() {
        let folder = TemporaryFolder()
        #expect(throws: MacError.fileNotFound) { try Fork(path: folder.path("None"), kind: .data, permission: .read) }
        #expect(throws: MacError.fileNotFound) { try Fork(path: folder.path("None"), kind: .resource, permission: .read) }
    }

    @Test func resourceForksFromAppleDoubleFiles() throws {
        let folder = TemporaryFolder()
        folder.write("File", [])
        var double = AppleDouble()
        double.finderInfo = FinderInfo(type: "APPL", creator: "ABCD")
        double.resourceFork = [1, 2, 3]
        folder.write("._File", double.bytes)
        let fork = try Fork(path: folder.path("File"), kind: .resource, permission: .readWrite)
        #expect(fork.size == 3)
        #expect(try read(fork, 10) == [1, 2, 3])
        try write(fork, [4, 5])
        try fork.close()
        let written = try AppleDouble(bytes: try #require(folder.read("._File")))
        #expect(written.resourceFork == [1, 2, 3, 4, 5])
        // The Finder info is kept.
        #expect(written.finderInfo?.creator == "ABCD")
    }

    @Test func aResourceForkWrittenToAFileWithNoneIsMade() throws {
        let folder = TemporaryFolder()
        folder.write("File", [9])
        let fork = try Fork(path: folder.path("File"), kind: .resource, permission: .readWrite)
        #expect(fork.size == 0)
        try write(fork, [7, 7])
        try fork.flush()
        #expect(try AppleDouble(bytes: try #require(folder.read("._File"))).resourceFork == [7, 7])
        #expect(folder.read("File") == [9])
    }

    @Test func resourceForksFromRsrcFiles() throws {
        let folder = TemporaryFolder()
        folder.write("Game", [])
        folder.write("Game.rsrc", [5, 6])
        let fork = try Fork(path: folder.path("Game"), kind: .resource, permission: .readWrite)
        #expect(try read(fork, 10) == [5, 6])
        try write(fork, [8], at: .start(0))
        try fork.close()
        #expect(folder.read("Game.rsrc") == [8, 6])
        #expect(!folder.exists("._Game"))
    }

    @Test func rsrcFilesMayBeAppleDouble() throws {
        let folder = TemporaryFolder()
        folder.write("Game", [])
        var double = AppleDouble()
        double.resourceFork = [3, 1, 4]
        folder.write("Game.rsrc", double.bytes)
        let fork = try Fork(path: folder.path("Game"), kind: .resource, permission: .read)
        #expect(try read(fork, 10) == [3, 1, 4])
    }

    @Test func permissionBytes() {
        #expect(ForkPermission(0) == .current)
        #expect(ForkPermission(1) == .read)
        #expect(ForkPermission(2) == .write)
        #expect(ForkPermission(3) == .readWrite)
        #expect(ForkPosition(mode: 0, offset: 9) == .mark(0))
        #expect(ForkPosition(mode: 1, offset: 9) == .start(9))
        #expect(ForkPosition(mode: 2, offset: -1) == .end(-1))
        #expect(ForkPosition(mode: 3, offset: 2) == .mark(2))
    }
}
