import Testing
import GraphiteBase
import GraphiteFiles
import GraphiteResources

@Suite struct ResourceChainTests {

    /// A file whose resource fork is in "._name", as macOS copies it.
    private func makeFile(_ folder: TemporaryFolder, _ name: String, _ resources: [(Resource, [UInt8])]) throws {
        folder.write(name, [])
        var double = AppleDouble()
        double.resourceFork = try ResourceMap.write(resources.map { (resource: $0.0, bytes: $0.1) })
        folder.write("._" + name, double.bytes)
    }

    @Test func getSearchesBackFromTheCurrentFile() throws {
        let folder = TemporaryFolder()
        try makeFile(folder, "Application", [(Resource(type: "TEXT", id: 1), [1]), (Resource(type: "TEXT", id: 2), [2])])
        try makeFile(folder, "Document", [(Resource(type: "TEXT", id: 1, name: "One"), [10])])
        let chain = ResourceChain(fileSystem: FileSystem(defaultFolder: folder.path))
        let application = try chain.open(folder.path("Application"))
        let document = try chain.open(folder.path("Document"))
        #expect(chain.current == document)
        #expect(try chain.get(type: "TEXT", id: 1).bytes == [10])
        #expect(try chain.get(type: "TEXT", id: 2).reference == application)
        #expect(throws: MacError.resourceNotFound) { try chain.get(type: "TEXT", id: 2, oneFile: true) }
        #expect(try chain.get(type: "TEXT", named: "One").resource.id == 1)
        #expect(chain.count(type: "TEXT") == 3)
        #expect(chain.count(type: "TEXT", oneFile: true) == 1)
        #expect(try chain.get(type: "TEXT", index: 3).bytes == [2])
        #expect(chain.types() == ["TEXT"])
        try chain.use(application)
        #expect(try chain.get(type: "TEXT", id: 1).bytes == [1])
        #expect(throws: MacError.resourceFileNotFound) { try chain.use(999) }
        try chain.close(application)
        #expect(chain.current == document)
        #expect(throws: MacError.resourceFileNotFound) { try chain.close(application) }
    }

    @Test func openingAFileAgainGivesItsNumber() throws {
        let folder = TemporaryFolder()
        try makeFile(folder, "File", [(Resource(type: "TEXT", id: 1), [1])])
        let chain = ResourceChain(fileSystem: FileSystem(defaultFolder: folder.path))
        let first = try chain.open(folder.path("File"))
        #expect(try chain.open(folder.path("File")) == first)
        #expect(chain.files.count == 1)
    }

    @Test func filesWithoutResourceForks() throws {
        let folder = TemporaryFolder()
        folder.write("Plain", [1, 2, 3])
        let files = FileSystem(defaultFolder: folder.path)
        let chain = ResourceChain(fileSystem: files)
        #expect(throws: MacError.endOfFile) { try chain.open(folder.path("Plain")) }
        #expect(throws: MacError.fileNotFound) { try chain.open(folder.path("None")) }
        // The fork it opened is closed again.
        #expect(files.openForks.isEmpty)
    }

    @Test func dataForkResourceFiles() throws {
        let folder = TemporaryFolder()
        folder.write("Game.rsrc", try ResourceMap.write([(Resource(type: "snd ", id: 128), [9, 9])]))
        let chain = ResourceChain(fileSystem: FileSystem(defaultFolder: folder.path))
        try chain.open(folder.path("Game.rsrc"), fork: .data)
        #expect(try chain.get(type: "snd ", id: 128).bytes == [9, 9])
    }

    @Test func setResLoad() throws {
        let folder = TemporaryFolder()
        try makeFile(folder, "File", [(Resource(type: "TEXT", id: 1), [1])])
        let chain = ResourceChain(fileSystem: FileSystem(defaultFolder: folder.path))
        try chain.open(folder.path("File"))
        chain.loadsResources = false
        #expect(try chain.get(type: "TEXT", id: 1).bytes == nil)
    }

    @Test func changesAreWrittenBack() throws {
        let folder = TemporaryFolder()
        try makeFile(folder, "Prefs", [
            (Resource(type: "PREF", id: 128), [1]),
            (Resource(type: "PREF", id: 129), [2]),
            (Resource(type: "LOCK", id: 1, attributes: .protected), [3]),
        ])
        let files = FileSystem(defaultFolder: folder.path)
        let chain = ResourceChain(fileSystem: files)
        let reference = try chain.open(folder.path("Prefs"), permission: .readWrite)
        let file = try #require(chain.file(reference))
        try file.setBytes([7, 7], type: "PREF", id: 128)
        try file.remove(type: "PREF", id: 129)
        try file.add(Resource(type: "NEW ", id: 5, name: "Five"), bytes: [5])
        #expect(throws: MacError.addResourceFailed) { try file.add(Resource(type: "NEW ", id: 5), bytes: []) }
        try file.setInfo(type: "NEW ", id: 5, newID: 6, name: .some("Six"))
        #expect(throws: MacError.resourceAttribute) { try file.setBytes([], type: "LOCK", id: 1) }
        #expect(throws: MacError.removeResourceFailed) { try file.remove(type: "LOCK", id: 1) }
        #expect(file.uniqueID(type: "PREF") == 129)
        #expect(file.isChanged)
        try chain.close(reference)

        let again = ResourceChain(fileSystem: files)
        try again.open(folder.path("Prefs"))
        #expect(try again.get(type: "PREF", id: 128).bytes == [7, 7])
        #expect(throws: MacError.resourceNotFound) { try again.get(type: "PREF", id: 129) }
        let six = try again.get(type: "NEW ", id: 6)
        #expect(six.bytes == [5])
        #expect(six.resource.name == "Six")
        // resChanged isn't written.
        #expect(!six.resource.attributes.contains(.changed))
        #expect(try again.get(type: "LOCK", id: 1).resource.attributes == .protected)
    }

    @Test func readOnlyFilesDontChange() throws {
        let folder = TemporaryFolder()
        try makeFile(folder, "File", [(Resource(type: "TEXT", id: 1), [1])])
        let chain = ResourceChain(fileSystem: FileSystem(defaultFolder: folder.path))
        let reference = try chain.open(folder.path("File"), permission: .read)
        let file = try #require(chain.file(reference))
        #expect(file.attributes.contains(.readOnly))
        #expect(throws: MacError.writePermission) { try file.setBytes([2], type: "TEXT", id: 1) }
    }

    @Test func createResourceFiles() throws {
        let folder = TemporaryFolder()
        let files = FileSystem(defaultFolder: folder.path)
        let chain = ResourceChain(fileSystem: files)
        try chain.create(folder.path("New"), finderInfo: FinderInfo(type: "rsrc", creator: "RSED"))
        #expect(try files.finderInfo(at: folder.path("New")).creator == "RSED")
        let reference = try chain.open(folder.path("New"), permission: .readWrite)
        let file = try #require(chain.file(reference))
        #expect(file.resources.isEmpty)
        try file.add(Resource(type: "TEXT", id: 128), bytes: Array("hi".utf8))
        try chain.update(reference)
        #expect(throws: MacError.duplicateFileName) { try chain.create(folder.path("New")) }
        try chain.close(reference)
        #expect(try ResourceChain(fileSystem: files).open(bytes: AppleDouble(bytes: folder.read("._New")!).resourceFork!) < 0)
    }
}
