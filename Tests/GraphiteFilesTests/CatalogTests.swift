import Testing
import GraphiteBase
import GraphiteFiles

@Suite struct CatalogTests {

    @Test func appleDoubleRoundTrip() throws {
        var double = AppleDouble()
        double[.realName] = Array("Name".utf8)
        double.finderInfo = FinderInfo(type: "TEXT", creator: "ttxt", flags: FinderInfo.isInvisibleFlag)
        double.resourceFork = [1, 2]
        let bytes = double.bytes
        #expect(Array(bytes[0 ..< 8]) == [0x00, 0x05, 0x16, 0x07, 0x00, 0x02, 0x00, 0x00])
        let read = try AppleDouble(bytes: bytes)
        #expect(read == double)
        // Finder info goes before the resource fork, as macOS writes it.
        #expect(read.entries.map(\.id) == [.realName, .finderInfo, .resourceFork])
        #expect(read.finderInfo?.type == "TEXT")
        #expect(read.finderInfo?.flags == FinderInfo.isInvisibleFlag)
    }

    @Test func finderInfoKeepsWhatFollowsIt() throws {
        // macOS keeps extended attributes after the Finder info's 32 bytes.
        var double = AppleDouble(entries: [AppleDouble.Entry(id: .finderInfo, bytes: [UInt8](repeating: 0, count: 32) + [9, 9, 9])])
        double.finderInfo = FinderInfo(type: "APPL", creator: "????")
        #expect(double[.finderInfo]?.suffix(3) == [9, 9, 9])
        #expect(double.finderInfo?.type == "APPL")
    }

    @Test func badAppleDoubleFilesThrow() {
        #expect(throws: MacError.self) { try AppleDouble(bytes: [0, 5, 0x16, 7]) }
        #expect(throws: MacError.self) { try AppleDouble(bytes: [1, 2, 3, 4, 5, 6, 7, 8]) }
        // An entry past the end.
        var bytes = AppleDouble(entries: [AppleDouble.Entry(id: .resourceFork, bytes: [1, 2, 3])]).bytes
        bytes.removeLast()
        #expect(throws: MacError.self) { try AppleDouble(bytes: bytes) }
    }

    @Test func finderInfoIsWrittenOnCreate() throws {
        let folder = TemporaryFolder()
        let files = FileSystem(defaultFolder: folder.path)
        try files.createFile(at: folder.path("Doc"), finderInfo: FinderInfo(type: "TEXT", creator: "R*ch"))
        let info = try files.catalogInfo(at: folder.path("Doc"))
        #expect(info.finderInfo.type == "TEXT")
        #expect(info.finderInfo.creator == "R*ch")
        try files.setFinderInfo(FinderInfo(type: "PICT", creator: "R*ch"), at: folder.path("Doc"))
        #expect(try files.finderInfo(at: folder.path("Doc")).type == "PICT")
    }

    @Test func createIsCaseInsensitive() throws {
        let folder = TemporaryFolder()
        folder.write("Read Me", [])
        let files = FileSystem(defaultFolder: folder.path)
        #expect(throws: MacError.duplicateFileName) { try files.createFile(at: folder.path("read me")) }
        #expect(throws: MacError.duplicateFileName) { try files.createDirectory(at: folder.path("READ ME")) }
    }

    @Test func catalogInfo() throws {
        let folder = TemporaryFolder()
        folder.makeFolder("Folder")
        folder.write("Folder/a", [1, 2, 3])
        folder.write("Folder/b", [])
        folder.write("Folder/._b", AppleDouble(entries: [AppleDouble.Entry(id: .resourceFork, bytes: [1, 2, 3, 4])]).bytes)
        let files = FileSystem(defaultFolder: folder.path)
        let directory = try files.catalogInfo(at: folder.path("Folder"))
        #expect(directory.isDirectory)
        // The AppleDouble file isn't an item.
        #expect(directory.valence == 2)
        #expect(files.path(ofDirectory: DirectoryID(directory.nodeID)) == folder.path("Folder"))
        let a = try files.catalogInfo(at: folder.path("Folder/a"))
        #expect(!a.isDirectory)
        #expect(a.dataLogicalSize == 3)
        #expect(a.parentID.rawValue == directory.nodeID)
        let b = try files.catalogInfo(at: folder.path("Folder/b"))
        #expect(b.resourceLogicalSize == 4)
        #expect(try files.catalogInfo(at: "/").parentID == .rootParent)
        #expect(throws: MacError.fileNotFound) { try files.catalogInfo(at: folder.path("None")) }
    }

    @Test func resourceForksMoveWithTheirFiles() throws {
        let folder = TemporaryFolder()
        folder.makeFolder("To")
        folder.write("File", [])
        folder.write("._File", AppleDouble(entries: [AppleDouble.Entry(id: .resourceFork, bytes: [1])]).bytes)
        let files = FileSystem(defaultFolder: folder.path)
        let renamed = try files.rename(at: folder.path("File"), to: "Renamed")
        #expect(folder.exists("._Renamed") && !folder.exists("._File"))
        let moved = try files.move(at: renamed, into: folder.path("To"))
        #expect(moved == folder.path("To/Renamed"))
        #expect(folder.exists("To/._Renamed"))
        #expect(try files.contents(ofFolder: folder.path("To")) == ["Renamed"])
        try files.delete(at: moved)
        #expect(!folder.exists("To/._Renamed"))
        #expect(try files.contents(ofFolder: folder.path("To")).isEmpty)
    }

    @Test func renamingInAnotherCase() throws {
        let folder = TemporaryFolder()
        folder.write("name", [])
        folder.write("other", [])
        let files = FileSystem(defaultFolder: folder.path)
        #expect(throws: MacError.duplicateFileName) { try files.rename(at: folder.path("name"), to: "Other") }
        let renamed = try files.rename(at: folder.path("name"), to: "Name")
        #expect(renamed == folder.path("Name"))
    }

    @Test func foldersWithOnlyAppleDoubleFilesAreEmpty() throws {
        let folder = TemporaryFolder()
        folder.makeFolder("F")
        folder.write("F/._gone", [])
        let files = FileSystem(defaultFolder: folder.path)
        try files.delete(at: folder.path("F"))
        #expect(!folder.exists("F"))
        folder.makeFolder("G")
        folder.write("G/kept", [])
        #expect(throws: MacError.fileBusy) { try files.delete(at: folder.path("G")) }
    }

    @Test func hiddenItems() throws {
        let folder = TemporaryFolder()
        folder.write(".hidden", [])
        folder.write("shown", [])
        let files = FileSystem(defaultFolder: folder.path)
        #expect(try files.contents(ofFolder: folder.path).sorted() == [".hidden", "shown"])
        #expect(try files.contents(ofFolder: folder.path, includingHidden: false) == ["shown"])
    }

    @Test func volumeSpace() {
        let space = Volume.Space(total: 10 << 30, free: 1 << 30)
        let classic = space.classic
        // At most 2 GB, in at most 65535 blocks.
        #expect(UInt64(classic.blockSize) * UInt64(classic.blocks) <= 0x7FFF_FFFF)
        #expect(classic.blockSize == 32768)
        #expect(classic.freeBlocks == UInt16((1 << 30) / 32768))
        #expect(Volume(spacePath: "/").space != nil)
    }
}
