import Testing
import GraphiteBase
import GraphiteFiles

@Suite struct FileSpecTests {

    @Test(arguments: [
        ("a", "/f/a"),
        (":a:b", "/f/a/b"),
        ("::a", "/f/../a"),
        (":::a", "/f/../../a"),
        (":a::b", "/f/a/../b"),
        (":a:", "/f/a"),
        // A colon after the first character: from a volume's root.
        ("a:b", "/b"),
        ("Macintosh HD:Users:x", "/Users/x"),
        ("Macintosh HD:", "/"),
        ("a/b", "/f/a:b"),
        ("", "/f"),
    ])
    func colonPaths(name: String, path: String) {
        #expect(ColonPath.join(folder: "/f", name: PascalString(name)!) == path)
    }

    @Test func namesSwapColonsAndSlashes() {
        #expect(FileNames.hfs("a:b") == "a/b")
        #expect(FileNames.posix("a/b") == "a:b")
    }

    @Test func specNamesAreMacRoman() {
        #expect(FileNames.specName("Café", id: 1).bytes == [0x43, 0x61, 0x66, 0x8E])
        #expect(FileNames.specName("a:b", id: 1).string == "a/b")
    }

    @Test func longNamesAreMangledWithTheirID() {
        let name = String(repeating: "x", count: 80)
        let spec = FileNames.specName(name, id: 0x1A2B)
        #expect(spec.count == 63)
        #expect(spec.string.hasSuffix("#1A2B"))
    }

    @Test func specsRoundTrip() throws {
        let folder = TemporaryFolder()
        folder.makeFolder("Data")
        folder.write("Data/File", [1])
        let files = FileSystem(defaultFolder: folder.path)
        let spec = files.spec(forPath: folder.path("Data/File"))
        #expect(spec.volume == -100)
        #expect(spec.name == "File")
        #expect(files.path(of: spec) == folder.path("Data/File"))
        #expect(files.path(ofDirectory: spec.parent) == folder.path("Data"))
    }

    @Test func theRootIsTwoAndItsParentOne() {
        let files = FileSystem()
        #expect(files.directoryID(ofFolder: "/") == .root)
        #expect(files.spec(forPath: "/").parent == .rootParent)
        #expect(files.spec(forPath: "/").name == "Macintosh HD")
        #expect(files.path(ofDirectory: .root) == "/")
    }

    @Test func makeSpecFromTheDefaultFolder() throws {
        let folder = TemporaryFolder()
        folder.makeFolder("Resources")
        folder.makeFolder("Resources/Data")
        folder.write("Resources/Data/Level1", [])
        folder.makeFolder("MacOS")
        let files = FileSystem(defaultFolder: folder.path("MacOS"))
        // Pangea's games find their data so.
        let (spec, exists) = try files.makeSpec(volume: 0, directory: 0, name: "::Resources:Data:Level1")
        #expect(exists)
        #expect(files.path(of: spec) == folder.path("Resources/Data/Level1"))
    }

    @Test func makeSpecOfAnItemNotThereYet() throws {
        let folder = TemporaryFolder()
        let files = FileSystem(defaultFolder: folder.path)
        let (spec, exists) = try files.makeSpec(volume: 0, directory: 0, name: "New")
        #expect(!exists)
        #expect(files.path(of: spec) == folder.path("New"))
        #expect(throws: MacError.directoryNotFound) { try files.makeSpec(volume: 0, directory: 0, name: ":Missing:New") }
    }

    @Test func namesAreFoundInAnyCase() throws {
        let folder = TemporaryFolder()
        folder.makeFolder("Shaders")
        folder.write("Shaders/FX", [])
        let files = FileSystem(defaultFolder: folder.path)
        let (spec, exists) = try files.makeSpec(volume: 0, directory: 0, name: ":shaders:fx")
        #expect(exists)
        #expect(files.path(of: spec) == folder.path("Shaders/FX"))
        // A file system that tells no case apart finds it as spelled.
        #expect(files.lookUp(folder.path("SHADERS/fx"))?.lowercased() == folder.path("Shaders/FX").lowercased())
    }

    @Test func mangledNamesAreFoundByTheirID() throws {
        let folder = TemporaryFolder()
        let name = String(repeating: "y", count: 80)
        folder.write(name, [])
        let files = FileSystem(defaultFolder: folder.path)
        let spec = files.spec(forPath: folder.path(name))
        #expect(spec.name.count == 63)
        #expect(files.path(of: spec) == folder.path(name))
    }

    @Test func folderIDsStayAcrossRenames() throws {
        let folder = TemporaryFolder()
        folder.makeFolder("Old")
        let files = FileSystem(defaultFolder: folder.path)
        let id = try #require(files.directoryID(ofFolder: folder.path("Old")))
        try files.rename(at: folder.path("Old"), to: "New")
        #expect(files.path(ofDirectory: id) == folder.path("New"))
        #expect(files.directoryID(ofFolder: folder.path("New")) == id)
    }

    @Test func unseenFolderIDsAreLookedFor() throws {
        let folder = TemporaryFolder()
        folder.makeFolder("a")
        folder.makeFolder("a/b")
        // Its inode, as another provider's catalog information gives it.
        let inode = try FileSystem().catalogInfo(at: folder.path("a/b")).nodeID
        let files = FileSystem(knownFolders: [folder.path])
        #expect(files.path(ofDirectory: DirectoryID(inode)) == folder.path("a/b"))
    }

    @Test func theDefaultFolderCanBeSet() throws {
        let folder = TemporaryFolder()
        folder.makeFolder("Data")
        let files = FileSystem(defaultFolder: folder.path)
        let data = try #require(files.directoryID(ofFolder: folder.path("Data")))
        try files.setDefaultDirectory(volume: 0, directory: data)
        #expect(files.defaultDirectory.path == folder.path("Data"))
        #expect(throws: MacError.noSuchVolume) { try files.setDefaultDirectory(volume: 5, directory: data) }
    }
}
