// The File Manager's catalog over a POSIX file system: one volume,
// "Macintosh HD" (-100), at the root; folder IDs are inodes, with the root
// as 2; names in FSSpecs are MacRoman. A Mac's file system tells no case
// apart, so a name not there as spelled is looked
// for in any case. A file's resource fork and Finder info are kept in an
// AppleDouble file beside it ("._name"), which moves, is renamed and is
// deleted with it and isn't listed in its folder.

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
#if canImport(System)
import System
#else
import SystemPackage
#endif
import Synchronization
import GraphiteBase

public final class FileSystem: Sendable {

    /// The one volume, the root.
    public let volume: Volume

    struct State {
        /// Folders seen, by ID, and their IDs by device and inode.
        var paths: [DirectoryID: String] = [:]
        var ids: [DeviceInode: DirectoryID] = [:]
        /// IDs for folders whose inodes can't be theirs: 1 or 2 below the
        /// root, or one another folder has.
        var nextMadeID: UInt32 = 0x7F00_0000
        var seeded = false
        var knownFolders: [String]
        /// HGetVol's folder, its ID made when it's first asked for.
        var defaultFolder: String
        var defaultDirectory: DirectoryID?
        var folders: FolderLocations
        var forks: [Int16: OpenFork] = [:]
    }

    struct DeviceInode: Hashable {
        var device: UInt64
        var inode: UInt64
    }

    let state: Mutex<State>

    /// - Parameters:
    ///   - defaultFolder: HGetVol's folder, where names from folder 0 are;
    ///     the working folder by default.
    ///   - knownFolders: folders whose IDs, and their parents', are known
    ///     from the start, so that a program that keeps one finds it again.
    ///     The working folder and the home are known whatever is given.
    ///   - folders: where FindFolder's folders are.
    ///   - volume: the volume's name and where its space is counted.
    public init(
        defaultFolder: String? = nil,
        knownFolders: [String] = [],
        folders: FolderLocations = .xdg,
        volume: Volume = Volume()
    ) {
        self.volume = volume
        let working = POSIX.workingDirectory
        var known = [working] + knownFolders
        if let home = POSIX.environment("HOME") { known.append(home) }
        state = Mutex(State(knownFolders: known, defaultFolder: defaultFolder ?? working, folders: folders))
    }

    // MARK: Folder IDs

    /// A folder's ID, which names it from now on; nil if it isn't there.
    public func directoryID(ofFolder path: String) -> DirectoryID? {
        state.withLock { Self.directoryID(ofFolder: path, in: &$0) }
    }

    static func directoryID(ofFolder path: String, in state: inout State) -> DirectoryID? {
        guard let item = ItemStatus(path: path) else { return nil }
        guard let root = ItemStatus(path: "/") else { return nil }
        // The root is 2 whatever its inode: an overlay's or a squashed
        // image's isn't.
        if item.device == root.device, item.inode == root.inode { return .root }
        let key = DeviceInode(device: item.device, inode: item.inode)
        if let id = state.ids[key] { return id }
        var id = DirectoryID(UInt32(truncatingIfNeeded: item.inode))
        // An ext4 file system mounted below the root has a root of inode 2;
        // a btrfs subvolume's root is always 256.
        if id.rawValue <= DirectoryID.root.rawValue || state.paths[id] != nil {
            id = DirectoryID(state.nextMadeID)
            state.nextMadeID += 1
        }
        state.paths[id] = path
        state.ids[key] = id
        return id
    }

    /// The folder an ID names, of those seen, else looked for below them.
    public func path(ofDirectory id: DirectoryID) -> String? {
        state.withLock { Self.path(ofDirectory: id, in: &$0) }
    }

    static func path(ofDirectory id: DirectoryID, in state: inout State) -> String? {
        if id == .root || id == .rootParent { return "/" }
        if !state.seeded {
            state.seeded = true
            for folder in state.knownFolders {
                var path = Paths.standardized(folder)
                while path != "/" {
                    _ = directoryID(ofFolder: path, in: &state)
                    path = Paths.parent(of: path)
                }
            }
        }
        if let path = state.paths[id] { return path }
        // An ID from the catalog information of a folder this hasn't seen:
        // looked for in the folders below those it has, nearest first.
        let known = Array(state.paths.values)
        for depth in 1 ... 3 {
            for folder in known where folder != "/" {
                if let found = findFolder(withInode: id.rawValue, below: folder, depth: depth) {
                    _ = directoryID(ofFolder: found, in: &state)
                    if let path = state.paths[id] { return path }
                }
            }
        }
        return nil
    }

    private static func findFolder(withInode inode: UInt32, below folder: String, depth: Int) -> String? {
        guard let names = POSIX.names(inFolder: folder) else { return nil }
        for name in names where !name.hasPrefix(".") {
            let path = Paths.appending(name, to: folder)
            guard let item = ItemStatus(path: path), item.isDirectory else { continue }
            if depth == 1 {
                if UInt32(truncatingIfNeeded: item.inode) == inode { return path }
            } else if let found = findFolder(withInode: inode, below: path, depth: depth - 1) {
                return found
            }
        }
        return nil
    }

    // MARK: The default folder

    /// HGetVol's folder and its ID.
    public var defaultDirectory: (path: String, id: DirectoryID) {
        state.withLock { state in
            if let id = state.defaultDirectory, let path = state.paths[id] { return (path, id) }
            let id = Self.directoryID(ofFolder: state.defaultFolder, in: &state) ?? .root
            state.defaultDirectory = id
            return (state.paths[id] ?? "/", id)
        }
    }

    /// HSetVol: names from folder 0 are in this one from now on.
    public func setDefaultDirectory(volume: Int16, directory: DirectoryID) throws(MacError) {
        guard volume == 0 || volume == self.volume.reference else { throw .noSuchVolume }
        let result: MacError? = state.withLock { state in
            guard let path = Self.path(ofDirectory: directory, in: &state) else { return .directoryNotFound }
            state.defaultFolder = path
            state.defaultDirectory = directory
            return nil
        }
        if let result { throw result }
    }

    /// The folder a volume and folder ID name: the default folder for 0, the
    /// root for another volume's 0.
    public func folder(volume: Int16, directory: Int32) -> String? {
        if directory == 0 {
            if volume != 0 && volume != self.volume.reference { return "/" }
            return defaultDirectory.path
        }
        return path(ofDirectory: DirectoryID(UInt32(bitPattern: directory)))
    }

    // MARK: Names in any case

    /// The path of the item a path names: the path itself if it is there,
    /// else the one whose names match its in any case, or a long name's
    /// mangled for an FSSpec, if there is one.
    public func lookUp(_ path: String) -> String? {
        if ItemStatus.exists(path) { return path }
        var found = "/"
        for part in Paths.standardized(path).split(separator: "/") {
            let name = String(part)
            let exact = Paths.appending(name, to: found)
            if ItemStatus.exists(exact) {
                found = exact
                continue
            }
            guard let match = Self.match(name, inFolder: found) else { return nil }
            found = Paths.appending(match, to: found)
        }
        return found
    }

    /// The name in a folder that is `name` in another case, or that a
    /// mangled name's ID is.
    static func match(_ name: String, inFolder folder: String) -> String? {
        guard let names = POSIX.names(inFolder: folder) else { return nil }
        let wanted = name.lowercased()
        if let match = names.first(where: { $0.lowercased() == wanted }) { return match }
        if let id = FileNames.mangledID(name) {
            return names.first { ItemStatus(path: Paths.appending($0, to: folder)).map { UInt32(truncatingIfNeeded: $0.inode) } == id }
        }
        return nil
    }

    /// Whether a folder has an item of a name in any case, which a new item
    /// of the name would duplicate on a Mac.
    public func hasItem(named name: String, inFolder folder: String) -> Bool {
        let wanted = name.lowercased()
        return POSIX.names(inFolder: folder)?.contains { $0.lowercased() == wanted } ?? false
    }

    // MARK: FSSpecs

    /// The spec of the item at a path, whose folder's ID names the folder
    /// from now on.
    public func spec(forPath path: String) -> FileSpec {
        let path = Paths.standardized(path)
        if path == "/" { return FileSpec(volume: volume.reference, parent: .rootParent, name: PascalString(volume.name) ?? "Macintosh HD") }
        let parent = directoryID(ofFolder: Paths.parent(of: path)) ?? .root
        let id = ItemStatus(path: path).map { UInt32(truncatingIfNeeded: $0.inode) } ?? 0
        return FileSpec(volume: volume.reference, parent: parent, name: FileNames.specName(Paths.name(of: path), id: id))
    }

    /// The path a spec names, whether or not the item is there; nil if its
    /// folder isn't known.
    public func path(of spec: FileSpec) -> String? {
        if spec.parent == .rootParent { return "/" }
        guard let folder = folder(volume: spec.volume, directory: Int32(bitPattern: spec.parent.rawValue)) else { return nil }
        let candidates = FileNames.candidates(spec.name)
        for name in candidates {
            let path = ColonPath.join(folder: folder, name: PascalString(bytes: name == candidates[0] ? spec.name.bytes : Array(FileNames.hfs(name).utf8)))
            if let found = lookUp(path) { return found }
        }
        return ColonPath.join(folder: folder, name: spec.name)
    }

    /// FSMakeFSSpec: the spec of a name in a volume's folder. `exists` is
    /// false for an item that isn't there in a folder that is, which a
    /// program makes a spec of to create it.
    public func makeSpec(volume: Int16, directory: Int32, name: PascalString) throws(MacError) -> (spec: FileSpec, exists: Bool) {
        guard let folder = folder(volume: volume, directory: directory) else { throw .directoryNotFound }
        let path = ColonPath.join(folder: folder, name: name)
        if let found = lookUp(path), let resolved = POSIX.realPath(found) {
            return (spec(forPath: resolved), true)
        }
        let parent = Paths.parent(of: path)
        guard let found = lookUp(parent), let resolved = POSIX.realPath(found) else { throw .directoryNotFound }
        guard ItemStatus(path: resolved)?.isDirectory == true else { throw .directoryNotFound }
        return (spec(forPath: Paths.appending(Paths.name(of: path), to: resolved)), false)
    }

    // MARK: Making, moving and deleting

    /// The AppleDouble file that keeps an item's resource fork and Finder
    /// info: "._name" beside it.
    public static func appleDoublePath(of path: String) -> String {
        Paths.appending("._" + Paths.name(of: path), to: Paths.parent(of: path))
    }

    /// A new, empty file, with its Finder info if it has a type or creator.
    public func createFile(at path: String, finderInfo: FinderInfo? = nil) throws(MacError) {
        guard !hasItem(named: Paths.name(of: path), inFolder: Paths.parent(of: path)) else { throw .duplicateFileName }
        do {
            let file = try FileDescriptor.open(
                FilePath(path), .writeOnly, options: [.create, .exclusiveCreate], permissions: [.ownerReadWrite, .groupRead, .otherRead]
            )
            try? file.close()
        } catch let error as Errno {
            throw MacError(error)
        } catch {
            throw .io
        }
        if let finderInfo, !finderInfo.isEmpty { try setFinderInfo(finderInfo, at: path) }
    }

    /// A new folder, and its ID.
    @discardableResult
    public func createDirectory(at path: String) throws(MacError) -> DirectoryID {
        guard !hasItem(named: Paths.name(of: path), inFolder: Paths.parent(of: path)) else { throw .duplicateFileName }
        guard mkdir(path, 0o755) == 0 else { throw MacError(errno: errno) }
        return directoryID(ofFolder: path) ?? .root
    }

    /// Deletes a file, with its resource fork, or an empty folder.
    public func delete(at path: String) throws(MacError) {
        guard let item = ItemStatus(path: path) else { throw .fileNotFound }
        if item.isDirectory {
            // A folder whose only items are AppleDouble files is empty to
            // the program, which can't see them.
            if let names = POSIX.names(inFolder: path), names.allSatisfy({ $0.hasPrefix("._") }) {
                for name in names { unlink(Paths.appending(name, to: path)) }
            }
            guard rmdir(path) == 0 else { throw MacError(errno: errno) }
        } else {
            guard unlink(path) == 0 else { throw MacError(errno: errno) }
        }
        unlink(Self.appleDoublePath(of: path))
    }

    /// Renames an item in its folder, and its resource fork; its new path.
    @discardableResult
    public func rename(at path: String, to name: String) throws(MacError) -> String {
        let target = Paths.appending(name, to: Paths.parent(of: path))
        // Another item of the name, not this one in another case.
        if target.lowercased() != path.lowercased(), hasItem(named: name, inFolder: Paths.parent(of: path)) { throw .duplicateFileName }
        try move(path, to: target)
        return target
    }

    /// Moves an item into another folder, and its resource fork; its new
    /// path.
    @discardableResult
    public func move(at path: String, into folder: String) throws(MacError) -> String {
        guard ItemStatus(path: folder)?.isDirectory == true else { throw .directoryNotFound }
        let target = Paths.appending(Paths.name(of: path), to: folder)
        guard !hasItem(named: Paths.name(of: path), inFolder: folder) else { throw .duplicateFileName }
        try move(path, to: target)
        return target
    }

    private func move(_ path: String, to target: String) throws(MacError) {
        guard systemRename(path, target) == 0 else { throw MacError(errno: errno) }
        let double = Self.appleDoublePath(of: path)
        if ItemStatus.exists(double) { _ = systemRename(double, Self.appleDoublePath(of: target)) }
        // A folder's ID stays its own, at its new path.
        state.withLock { state in
            for (id, known) in state.paths where known == path || known.hasPrefix(path + "/") {
                state.paths[id] = target + known.dropFirst(path.count)
            }
            if state.defaultFolder == path || state.defaultFolder.hasPrefix(path + "/") {
                state.defaultFolder = target + state.defaultFolder.dropFirst(path.count)
            }
        }
    }

    // MARK: Folders' items

    /// The names in a folder a program sees: not its AppleDouble files, nor
    /// its invisible items unless `includingHidden`.
    public func contents(ofFolder path: String, includingHidden: Bool = true) throws(MacError) -> [String] {
        guard let item = ItemStatus(path: path) else { throw .directoryNotFound }
        guard item.isDirectory else { throw .directoryNotFound }
        guard let names = POSIX.names(inFolder: path) else { throw .permission }
        return names.filter { !$0.hasPrefix("._") && (includingHidden || !$0.hasPrefix(".")) }
    }
}

/// rename(2), which FileSystem's own rename hides.
private func systemRename(_ old: String, _ new: String) -> Int32 {
    rename(old, new)
}
