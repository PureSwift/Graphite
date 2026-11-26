// Aliases: records of an item that find it again after it moves. The
// Toolbox keeps an alias record opaque past its user type and size, which
// the layer that exports Carbon writes in its own byte order. After them
// Graphite keeps a mark, 'PRRY', the item's path and a zero; and after those
// its device and inode, so that an item that moved is found by them. A
// record with the path alone, as earlier records of the format have and
// programs may have kept in their preferences, resolves by its path.

import GraphiteBase

public struct Alias: Hashable, Sendable {

    /// The item's path when the alias was made.
    public var path: String

    /// The item's file system and inode, when known.
    public var device: UInt64?
    public var inode: UInt64?

    public var isDirectory: Bool

    public init(path: String, device: UInt64? = nil, inode: UInt64? = nil, isDirectory: Bool = false) {
        self.path = path
        self.device = device
        self.inode = inode
        self.isDirectory = isDirectory
    }

    /// FSNewAlias: an alias of the item at a path, which must be there.
    public init(target path: String) throws(MacError) {
        guard let item = ItemStatus(path: path) else { throw .fileNotFound }
        self.init(path: Paths.standardized(path), device: item.device, inode: item.inode, isDirectory: item.isDirectory)
    }

    /// 'PRRY', the mark of records of this format.
    public static var mark: FourCharCode { "PRRY" }

    /// The record after its user type and size.
    public var record: [UInt8] {
        var writer = BigEndianWriter()
        writer.write(Self.mark.rawValue)
        writer.write(bytes: path.utf8)
        writer.write(UInt8(0))
        if let device, let inode {
            writer.write(device)
            writer.write(inode)
            writer.write(UInt8(isDirectory ? 1 : 0))
        }
        return writer.bytes
    }

    /// An alias from its record after its user type and size: paramErr for
    /// one not of this format.
    public init(record: some Collection<UInt8>) throws(MacError) {
        let bytes = Array(record)
        var reader = BigEndianReader(bytes)
        guard let mark = try? reader.read(UInt32.self), mark == Self.mark.rawValue else { throw .parameter }
        guard let end = bytes[4...].firstIndex(of: 0) else { throw .parameter }
        path = String(decoding: bytes[4 ..< end], as: UTF8.self)
        guard !path.isEmpty else { throw .parameter }
        reader.offset = end + 1
        if reader.remaining >= 17 {
            device = try? reader.read(UInt64.self)
            inode = try? reader.read(UInt64.self)
            isDirectory = (try? reader.read(UInt8.self)) == 1
        } else {
            device = nil
            inode = nil
            isDirectory = false
        }
    }

    /// FSResolveAlias: the item's path now, and whether it isn't where the
    /// alias says. An item that moved is looked for by its inode near where
    /// it was: in the folders around its old one, up to three levels below
    /// the nearest that is still there and the program's known folders.
    public func resolve(in fileSystem: FileSystem? = nil) throws(MacError) -> (path: String, changed: Bool) {
        guard let device, let inode else {
            guard ItemStatus.exists(path) else { throw .fileNotFound }
            return (path, false)
        }
        if let item = ItemStatus(path: path), item.device == device, item.inode == inode, item.isDirectory == isDirectory {
            return (path, false)
        }
        var places: [String] = []
        var folder = Paths.parent(of: path)
        while true {
            if ItemStatus(path: folder)?.isDirectory == true {
                places.append(folder)
                if places.count == 2 { break }
            }
            if folder == "/" { break }
            folder = Paths.parent(of: folder)
        }
        if let fileSystem {
            places += fileSystem.state.withLock { Array($0.paths.values) }
        }
        var searched: Set<String> = []
        for place in places where place != "/" && searched.insert(place).inserted {
            if let found = Self.find(device: device, inode: inode, isDirectory: isDirectory, below: place, depth: 3) { return (found, true) }
        }
        // Not found where it was looked for: the item now at its path, if
        // there is one.
        guard ItemStatus.exists(path) else { throw .fileNotFound }
        return (path, true)
    }

    /// The item of a device and inode, of the kind the alias was made of: a
    /// file system may give a deleted file's inode to a folder.
    private static func find(device: UInt64, inode: UInt64, isDirectory: Bool, below folder: String, depth: Int) -> String? {
        guard depth > 0, let names = POSIX.names(inFolder: folder) else { return nil }
        var folders: [String] = []
        for name in names where !name.hasPrefix("._") {
            let path = Paths.appending(name, to: folder)
            guard let item = ItemStatus(path: path) else { continue }
            if item.device == device, item.inode == inode, item.isDirectory == isDirectory { return path }
            if item.isDirectory, !name.hasPrefix(".") { folders.append(path) }
        }
        for path in folders {
            if let found = find(device: device, inode: inode, isDirectory: isDirectory, below: path, depth: depth - 1) { return found }
        }
        return nil
    }
}
