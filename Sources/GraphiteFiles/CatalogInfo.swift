// What the catalog knows of an item: FSCatalogInfo's fields and the
// original File Manager's CInfoPBRec's, with Finder info from the item's
// AppleDouble file.

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import GraphiteBase

public struct CatalogInfo: Hashable, Sendable {

    public var isDirectory: Bool

    /// Not writable by the program.
    public var isLocked: Bool

    /// The folder the item is in; the root's is 1.
    public var parentID: DirectoryID

    /// A folder's ID; a file's inode.
    public var nodeID: UInt32

    public var created: MacDate
    public var contentModified: MacDate
    public var attributeModified: MacDate
    public var accessed: MacDate

    public var dataLogicalSize: Int64
    public var dataPhysicalSize: Int64
    public var resourceLogicalSize: Int64
    public var resourcePhysicalSize: Int64

    /// A folder's count of items a program sees.
    public var valence: UInt32

    public var finderInfo: FinderInfo

    public var ownerID: UInt32
    public var groupID: UInt32
    public var mode: UInt16

    public init(
        isDirectory: Bool, isLocked: Bool = false, parentID: DirectoryID, nodeID: UInt32,
        created: MacDate, contentModified: MacDate, attributeModified: MacDate, accessed: MacDate,
        dataLogicalSize: Int64 = 0, dataPhysicalSize: Int64 = 0, resourceLogicalSize: Int64 = 0, resourcePhysicalSize: Int64 = 0,
        valence: UInt32 = 0, finderInfo: FinderInfo = FinderInfo(), ownerID: UInt32 = 0, groupID: UInt32 = 0, mode: UInt16 = 0
    ) {
        self.isDirectory = isDirectory
        self.isLocked = isLocked
        self.parentID = parentID
        self.nodeID = nodeID
        self.created = created
        self.contentModified = contentModified
        self.attributeModified = attributeModified
        self.accessed = accessed
        self.dataLogicalSize = dataLogicalSize
        self.dataPhysicalSize = dataPhysicalSize
        self.resourceLogicalSize = resourceLogicalSize
        self.resourcePhysicalSize = resourcePhysicalSize
        self.valence = valence
        self.finderInfo = finderInfo
        self.ownerID = ownerID
        self.groupID = groupID
        self.mode = mode
    }
}

public extension FileSystem {

    /// An item's catalog information; its folder's ID, and its own if it is
    /// a folder, name them from now on.
    func catalogInfo(at path: String) throws(MacError) -> CatalogInfo {
        let path = Paths.standardized(path)
        guard let item = ItemStatus(path: path) else { throw .fileNotFound }
        let parent = path == "/" ? DirectoryID.rootParent : directoryID(ofFolder: Paths.parent(of: path)) ?? .root
        let node = item.isDirectory ? (directoryID(ofFolder: path) ?? .root).rawValue : UInt32(truncatingIfNeeded: item.inode)
        var info = CatalogInfo(
            isDirectory: item.isDirectory,
            isLocked: access(path, W_OK) != 0,
            parentID: parent,
            nodeID: node,
            created: MacDate(unixTime: item.created),
            contentModified: MacDate(unixTime: item.modified),
            attributeModified: MacDate(unixTime: item.changed),
            accessed: MacDate(unixTime: item.accessed),
            ownerID: 0,
            groupID: 0,
            mode: UInt16(truncatingIfNeeded: item.mode)
        )
        if item.isDirectory {
            info.valence = UInt32((try? contents(ofFolder: path))?.count ?? 0)
        } else {
            info.dataLogicalSize = item.size
            info.dataPhysicalSize = item.allocated
        }
        if let double = appleDouble(at: path) {
            if let finder = double.finderInfo { info.finderInfo = finder }
            if let fork = double.resourceFork {
                info.resourceLogicalSize = Int64(fork.count)
                info.resourcePhysicalSize = Int64((fork.count + 511) / 512 * 512)
            }
        } else if !item.isDirectory, let fork = ResourceForkStore.locate(for: path), fork.kind != .appleDouble {
            let size = Int64(fork.bytes.count)
            info.resourceLogicalSize = size
            info.resourcePhysicalSize = (size + 511) / 512 * 512
        }
        return info
    }

    /// An item's Finder info, zeros when it has none.
    func finderInfo(at path: String) throws(MacError) -> FinderInfo {
        guard ItemStatus.exists(path) else { throw .fileNotFound }
        return appleDouble(at: path)?.finderInfo ?? FinderInfo()
    }

    /// Keeps an item's Finder info in its AppleDouble file, made if it has
    /// none.
    func setFinderInfo(_ finderInfo: FinderInfo, at path: String) throws(MacError) {
        guard ItemStatus.exists(path) else { throw .fileNotFound }
        var double = appleDouble(at: path) ?? AppleDouble()
        if finderInfo.isEmpty, double.entries.isEmpty || double.entries.map(\.id) == [.finderInfo] {
            // Nothing to keep.
            unlink(Self.appleDoublePath(of: path))
            return
        }
        double.finderInfo = finderInfo
        try POSIX.writeFile(Self.appleDoublePath(of: path), double.bytes)
    }

    /// The item's AppleDouble file, if it has one that reads.
    func appleDouble(at path: String) -> AppleDouble? {
        guard let bytes = POSIX.readFile(Self.appleDoublePath(of: path)) else { return nil }
        return try? AppleDouble(bytes: bytes)
    }
}
