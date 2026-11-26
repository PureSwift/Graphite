import Testing
import GraphiteBase
import GraphiteFiles

@Suite struct AliasTests {

    @Test func recordsRoundTrip() throws {
        let folder = TemporaryFolder()
        folder.write("Target", [])
        let alias = try Alias(target: folder.path("Target"))
        let record = alias.record
        #expect(Array(record[0 ..< 4]) == Array("PRRY".utf8))
        #expect(try Alias(record: record) == alias)
        #expect(try alias.resolve() == (folder.path("Target"), false))
    }

    /// As earlier records of the format have it: the path alone.
    @Test func olderRecordsResolveByPath() throws {
        let folder = TemporaryFolder()
        folder.write("Target", [])
        let record = Array("PRRY".utf8) + Array(folder.path("Target").utf8) + [0]
        let alias = try Alias(record: record)
        #expect(alias.inode == nil)
        #expect(try alias.resolve().path == folder.path("Target"))
        #expect(throws: MacError.parameter) { try Alias(record: Array("NOPE/x".utf8) + [0]) }
    }

    @Test func aliasesFollowMovedItems() throws {
        let folder = TemporaryFolder()
        folder.makeFolder("Old")
        folder.makeFolder("New")
        folder.write("Old/Target", [])
        let alias = try Alias(target: folder.path("Old/Target"))
        let files = FileSystem(defaultFolder: folder.path)
        try files.move(at: folder.path("Old/Target"), into: folder.path("New"))
        let (path, changed) = try alias.resolve(in: files)
        #expect(path == folder.path("New/Target"))
        #expect(changed)
    }

    @Test func aliasesOfItemsGoneThrow() throws {
        let folder = TemporaryFolder()
        folder.write("Target", [])
        let alias = try Alias(target: folder.path("Target"))
        try FileSystem().delete(at: folder.path("Target"))
        #expect(throws: MacError.fileNotFound) { try alias.resolve() }
    }

    @Test func specialFolders() throws {
        let folder = TemporaryFolder()
        let files = FileSystem(folders: .macHome(folder.path))
        #expect(throws: MacError.fileNotFound) { try files.findFolder(FolderType.preferences, create: false) }
        let preferences = try files.findFolder(FolderType.preferences, create: true)
        #expect(preferences == folder.path("Library/Preferences"))
        #expect(folder.exists("Library/Preferences"))
        #expect(throws: MacError.fileNotFound) { try files.findFolder("zzzz", create: true) }
        #expect(FolderLocations.xdg.path(FolderType.caches) != nil)
    }
}
