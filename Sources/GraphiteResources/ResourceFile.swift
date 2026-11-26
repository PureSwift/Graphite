// A resource file: a fork's map and its resources' bytes, read when they're
// asked for, changed, added and removed in memory, and written back to the
// fork when it is updated or closed, as UpdateResFile and CloseResFile do.

import GraphiteBase
import GraphiteFiles

public final class ResourceFile {

    /// The fork the file was read from and is written to; nil for a file
    /// made from bytes alone.
    public let fork: Fork?

    /// The bytes the map was read from.
    private var source: [UInt8]

    private var map: ResourceMap

    /// Bytes of resources changed or added since the file was read.
    private var changedBytes: [ResourceKey: [UInt8]] = [:]

    public var attributes: ResourceFileAttributes {
        get { map.attributes }
        set { map.attributes = newValue }
    }

    /// Whether the file has changes not yet written.
    public var isChanged: Bool { map.attributes.contains(.changed) }

    struct ResourceKey: Hashable {
        var type: FourCharCode
        var id: Int16
    }

    /// The resources of a fork's bytes: mapReadErr for a damaged map.
    public init(bytes: [UInt8]) throws(MacError) {
        source = bytes
        map = try ResourceMap(parsing: bytes)
        fork = nil
    }

    /// A fork's resources. eofErr for an empty fork: a file with no
    /// resource fork, which FSCreateResFile would make one in.
    public init(fork: Fork) throws(MacError) {
        let size = fork.size
        guard size > 0 else { throw .endOfFile }
        guard size <= Int64(Int32.max) else { throw .mapRead }
        let bytes = try fork.readAll(count: Int(size))
        guard bytes.count == Int(size) else { throw .endOfFile }
        source = bytes
        map = try ResourceMap(parsing: bytes)
        self.fork = fork
        if !fork.canWrite { map.attributes.insert(.readOnly) }
    }

    // MARK: Finding resources

    /// Every resource, by type in the map's order.
    public var resources: [Resource] { map.entries.map(\.resource) }

    /// The types, in the map's order (Count1Types, Get1IndType).
    public var types: [FourCharCode] { map.types }

    /// The resources of a type, in the map's order.
    public func resources(ofType type: FourCharCode) -> [Resource] {
        map.entries.lazy.filter { $0.resource.type == type }.map(\.resource)
    }

    public func resource(type: FourCharCode, id: Int16) -> Resource? {
        map.entries.first { $0.resource.type == type && $0.resource.id == id }?.resource
    }

    /// The first resource of a type with a name, compared as the Resource
    /// Manager does: byte for byte.
    public func resource(type: FourCharCode, named name: PascalString) -> Resource? {
        map.entries.first { $0.resource.type == type && $0.resource.name == name }?.resource
    }

    /// A resource's bytes: resNotFound if the file hasn't it.
    public func bytes(type: FourCharCode, id: Int16) throws(MacError) -> [UInt8] {
        let key = ResourceKey(type: type, id: id)
        if let changed = changedBytes[key] { return changed }
        guard let entry = map.entries.first(where: { $0.resource.type == type && $0.resource.id == id }) else { throw .resourceNotFound }
        return Array(source[entry.data])
    }

    /// The size of a resource's bytes, without reading them
    /// (GetResourceSizeOnDisk, GetMaxResourceSize).
    public func size(type: FourCharCode, id: Int16) throws(MacError) -> Int {
        if let changed = changedBytes[ResourceKey(type: type, id: id)] { return changed.count }
        guard let entry = map.entries.first(where: { $0.resource.type == type && $0.resource.id == id }) else { throw .resourceNotFound }
        return entry.data.count
    }

    /// An ID no resource of the type has (UniqueID, Unique1ID): from 128,
    /// the first an application's own resources should use.
    public func uniqueID(type: FourCharCode) -> Int16 {
        let taken = Set(resources(ofType: type).map(\.id))
        var id: Int16 = 128
        while taken.contains(id), id < Int16.max { id += 1 }
        return id
    }

    // MARK: Changing resources

    private func index(type: FourCharCode, id: Int16) -> Int? {
        map.entries.firstIndex { $0.resource.type == type && $0.resource.id == id }
    }

    private func checkWritable() throws(MacError) {
        if map.attributes.contains(.readOnly) { throw .writePermission }
    }

    private func markChanged() {
        map.attributes.insert(.changed)
    }

    /// AddResource: addResFailed if the file has one of the type and ID.
    public func add(_ resource: Resource, bytes: [UInt8]) throws(MacError) {
        try checkWritable()
        guard index(type: resource.type, id: resource.id) == nil else { throw .addResourceFailed }
        var resource = resource
        resource.attributes.insert(.changed)
        // After the type's others, or at the end for a new type.
        let at = map.entries.lastIndex { $0.resource.type == resource.type }.map { $0 + 1 } ?? map.entries.count
        map.entries.insert(ResourceMap.Entry(resource: resource, data: 0 ..< 0), at: at)
        changedBytes[ResourceKey(type: resource.type, id: resource.id)] = bytes
        markChanged()
    }

    /// ChangedResource and WriteResource: the resource's bytes are these
    /// from now on. resAttrErr for a protected one.
    public func setBytes(_ bytes: [UInt8], type: FourCharCode, id: Int16) throws(MacError) {
        try checkWritable()
        guard let index = index(type: type, id: id) else { throw .resourceNotFound }
        guard !map.entries[index].resource.attributes.contains(.protected) else { throw .resourceAttribute }
        map.entries[index].resource.attributes.insert(.changed)
        changedBytes[ResourceKey(type: type, id: id)] = bytes
        markChanged()
    }

    /// RemoveResource: rmvResFailed for a protected one.
    public func remove(type: FourCharCode, id: Int16) throws(MacError) {
        try checkWritable()
        guard let index = index(type: type, id: id) else { throw .resourceNotFound }
        guard !map.entries[index].resource.attributes.contains(.protected) else { throw .removeResourceFailed }
        map.entries.remove(at: index)
        changedBytes[ResourceKey(type: type, id: id)] = nil
        markChanged()
    }

    /// SetResInfo: a new ID, a new name, or both; the bytes stay.
    public func setInfo(type: FourCharCode, id: Int16, newID: Int16? = nil, name: PascalString?? = nil) throws(MacError) {
        try checkWritable()
        guard let index = index(type: type, id: id) else { throw .resourceNotFound }
        guard !map.entries[index].resource.attributes.contains(.protected) else { throw .resourceAttribute }
        if let newID, newID != id {
            guard self.index(type: type, id: newID) == nil else { throw .addResourceFailed }
            let bytes = try self.bytes(type: type, id: id)
            changedBytes[ResourceKey(type: type, id: id)] = nil
            changedBytes[ResourceKey(type: type, id: newID)] = bytes
            map.entries[index].resource.id = newID
        }
        if let name { map.entries[index].resource.name = name }
        markChanged()
    }

    /// SetResAttrs: resChanged is the file's to set, and is kept.
    public func setAttributes(_ attributes: ResourceAttributes, type: FourCharCode, id: Int16) throws(MacError) {
        guard let index = index(type: type, id: id) else { throw .resourceNotFound }
        let changed = map.entries[index].resource.attributes.contains(.changed)
        map.entries[index].resource.attributes = attributes.subtracting(.changed)
        if changed { map.entries[index].resource.attributes.insert(.changed) }
        markChanged()
    }

    // MARK: Writing

    /// The file as a fork's bytes, its changes in them.
    public func write() throws(MacError) -> [UInt8] {
        var resources: [(resource: Resource, bytes: [UInt8])] = []
        resources.reserveCapacity(map.entries.count)
        for entry in map.entries {
            let key = ResourceKey(type: entry.resource.type, id: entry.resource.id)
            resources.append((entry.resource, changedBytes[key] ?? Array(source[entry.data])))
        }
        return try ResourceMap.write(resources, attributes: map.attributes, reservedHeader: map.reservedHeader)
    }

    /// UpdateResFile: writes the changes to the fork, if there are any.
    public func update() throws(MacError) {
        guard isChanged else { return }
        guard let fork else { throw .resourceFileNotFound }
        guard fork.canWrite else { throw .writePermission }
        let bytes = try write()
        try fork.replaceContents(with: bytes)
        // The file as it now is on disk.
        source = bytes
        map = try ResourceMap(parsing: bytes)
        changedBytes = [:]
    }
}

extension Fork {

    /// Up to `count` bytes from the fork's start.
    func readAll(count: Int) throws(MacError) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        var result = Result<Int, MacError>.success(0)
        bytes.withUnsafeMutableBytes { buffer in
            result = Result { () throws(MacError) -> Int in try read(into: buffer, from: .start(0)) }
        }
        bytes.removeLast(count - (try result.get()))
        return bytes
    }

    /// The fork's bytes are these, written out.
    func replaceContents(with bytes: [UInt8]) throws(MacError) {
        try setSize(0)
        var result = Result<Int, MacError>.success(0)
        bytes.withUnsafeBytes { buffer in
            result = Result { () throws(MacError) -> Int in try write(buffer, at: .start(0)) }
        }
        _ = try result.get()
        try flush()
    }
}
