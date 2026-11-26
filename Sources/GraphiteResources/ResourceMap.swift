// A resource fork's layout (Inside Macintosh: More Macintosh Toolbox, 1-121):
//
//     header    data offset, map offset, data length, map length (4 bytes each)
//     data      each resource's length (4) and bytes
//     map       a copy of the header, two words of the Resource Manager's,
//               the file's attributes, the type list's offset and the name
//               list's, from the map's start
//     types     their count less one, then each type, its count of
//               resources less one and its reference list's offset from
//               the type list's start
//     references  each resource's ID, its name's offset in the name list
//               (-1 for none), its attributes and its data's offset (3
//               bytes) from the data's start, and a handle's word
//     names     Pascal strings
//
// Every offset is checked: a map that points outside its fork throws
// mapReadErr, whatever its bytes say.

import protocol Foundation.ContiguousBytes
import struct Foundation.Data
import GraphiteBase

/// A resource's attributes.
public struct ResourceAttributes: OptionSet, Hashable, Sendable {

    public var rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// resSysHeap.
    public static var systemHeap: ResourceAttributes { ResourceAttributes(rawValue: 0x40) }
    /// resPurgeable.
    public static var purgeable: ResourceAttributes { ResourceAttributes(rawValue: 0x20) }
    /// resLocked.
    public static var locked: ResourceAttributes { ResourceAttributes(rawValue: 0x10) }
    /// resProtected: it can't be changed or removed.
    public static var protected: ResourceAttributes { ResourceAttributes(rawValue: 0x08) }
    /// resPreload.
    public static var preload: ResourceAttributes { ResourceAttributes(rawValue: 0x04) }
    /// resChanged: to be written when the file is updated.
    public static var changed: ResourceAttributes { ResourceAttributes(rawValue: 0x02) }
}

/// A resource file's attributes.
public struct ResourceFileAttributes: OptionSet, Hashable, Sendable {

    public var rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    /// mapReadOnly.
    public static var readOnly: ResourceFileAttributes { ResourceFileAttributes(rawValue: 0x80) }
    /// mapCompact: to be compacted when written.
    public static var compact: ResourceFileAttributes { ResourceFileAttributes(rawValue: 0x40) }
    /// mapChanged: to be written when the file is closed or updated.
    public static var changed: ResourceFileAttributes { ResourceFileAttributes(rawValue: 0x20) }
}

/// A resource, without its bytes.
public struct Resource: Hashable, Sendable {

    public var type: FourCharCode

    public var id: Int16

    public var name: PascalString?

    public var attributes: ResourceAttributes

    public init(type: FourCharCode, id: Int16, name: PascalString? = nil, attributes: ResourceAttributes = []) {
        self.type = type
        self.id = id
        self.name = name
        self.attributes = attributes
    }
}

/// A resource fork's map: its resources, in order, and where their bytes
/// are.
public struct ResourceMap: Hashable, Sendable {

    public struct Entry: Hashable, Sendable {

        public var resource: Resource

        /// The resource's bytes in the fork: after their length.
        public var data: Range<Int>

        public init(resource: Resource, data: Range<Int>) {
            self.resource = resource
            self.data = data
        }
    }

    public var attributes: ResourceFileAttributes

    /// By type, in the order of the type list, then in each type's order.
    public var entries: [Entry]

    /// The 112 bytes after the header the system kept for itself and the
    /// 128 the application could use: kept as they were when the file is
    /// written again.
    public var reservedHeader: [UInt8]

    public init(attributes: ResourceFileAttributes = [], entries: [Entry] = [], reservedHeader: [UInt8] = []) {
        self.attributes = attributes
        self.entries = entries
        self.reservedHeader = reservedHeader
    }

    /// The map of a fork's bytes: mapReadErr if any offset in it is outside
    /// them, eofErr if there are too few for a header.
    public init(parsing contents: some ContiguousBytes) throws(MacError) {
        let bytes = Data(zeroBased: contents)
        guard bytes.count >= 16 else { throw .endOfFile }
        do {
            var header = BigEndianReader(bytes)
            let dataOffset = Int(try header.read(UInt32.self))
            let mapOffset = Int(try header.read(UInt32.self))
            let dataLength = Int(try header.read(UInt32.self))
            let mapLength = Int(try header.read(UInt32.self))
            guard dataOffset <= bytes.count, dataLength <= bytes.count - dataOffset,
                  mapOffset <= bytes.count, mapLength <= bytes.count - mapOffset, mapLength >= 28 else { throw MacError.mapRead }
            let map = try BigEndianReader(bytes).subreader(at: mapOffset, count: mapLength)
            reservedHeader = dataOffset >= 256 ? Array(bytes[16 ..< 256]) : []
            attributes = ResourceFileAttributes(rawValue: try map.peek(UInt16.self, at: 22))
            let typeList = Int(try map.peek(UInt16.self, at: 24))
            let nameList = Int(try map.peek(UInt16.self, at: 26))
            entries = []
            // An empty map's type count is -1 (0xFFFF), or its type list is
            // at its end.
            guard typeList + 2 <= map.count else { return }
            let typeCount = (Int(try map.peek(UInt16.self, at: typeList)) + 1) & 0xFFFF
            var types = try map.subreader(at: typeList + 2, count: 8 * typeCount)
            for _ in 0 ..< typeCount {
                let type = FourCharCode(try types.read(UInt32.self))
                let count = Int(try types.read(UInt16.self)) + 1
                let references = Int(try types.read(UInt16.self))
                var list = try map.subreader(at: typeList + references, count: 12 * count)
                for _ in 0 ..< count {
                    let id = Int16(bitPattern: try list.read(UInt16.self))
                    let nameOffset = try list.read(UInt16.self)
                    let attributes = ResourceAttributes(rawValue: try list.read(UInt8.self))
                    let offset = Int(try list.read(UInt8.self)) << 16 | Int(try list.read(UInt16.self))
                    try list.skip(4)
                    var name: PascalString?
                    if nameOffset != 0xFFFF {
                        let at = nameList + Int(nameOffset)
                        let length = Int(try map.peek(UInt8.self, at: at))
                        name = PascalString(bytes: try map.subreader(at: at + 1, count: length).bytes)
                    }
                    guard offset + 4 <= dataLength else { throw MacError.mapRead }
                    let length = Int(try header.peek(UInt32.self, at: dataOffset + offset))
                    guard length <= dataLength - offset - 4 else { throw MacError.mapRead }
                    let start = dataOffset + offset + 4
                    entries.append(Entry(resource: Resource(type: type, id: id, name: name, attributes: attributes), data: start ..< start + length))
                }
            }
        } catch let error as MacError {
            throw error
        } catch {
            throw .mapRead
        }
    }

    /// The types, in the order of the type list.
    public var types: [FourCharCode] {
        var seen: Set<FourCharCode> = []
        return entries.compactMap { seen.insert($0.resource.type).inserted ? $0.resource.type : nil }
    }

    /// A fork with these resources: the bytes of each from `data`, in the
    /// map's order, with each type's resources kept together.
    public static func write(_ resources: [(resource: Resource, bytes: [UInt8])], attributes: ResourceFileAttributes = [],
                             reservedHeader: [UInt8] = []) throws(MacError) -> [UInt8] {
        // Each type's resources together, the types in the order they first
        // come.
        var order: [FourCharCode] = []
        var byType: [FourCharCode: [(resource: Resource, bytes: [UInt8])]] = [:]
        for item in resources {
            if byType[item.resource.type] == nil { order.append(item.resource.type) }
            byType[item.resource.type, default: []].append(item)
        }
        guard order.count <= 0x10000 else { throw .addResourceFailed }

        let dataOffset = 256
        var data = BigEndianWriter()
        var names = BigEndianWriter()
        var references = BigEndianWriter()
        var types = BigEndianWriter()
        let typeListSize = 2 + 8 * order.count
        types.write(UInt16(truncatingIfNeeded: order.count - 1))
        for type in order {
            let items = byType[type] ?? []
            guard items.count <= 0x10000 else { throw .addResourceFailed }
            types.write(type.rawValue)
            types.write(UInt16(items.count - 1))
            types.write(UInt16(typeListSize + references.count))
            for item in items {
                guard data.count <= 0xFF_FFFF else { throw .addResourceFailed }
                references.write(UInt16(bitPattern: item.resource.id))
                if let name = item.resource.name {
                    guard names.count <= 0xFFFE else { throw .addResourceFailed }
                    references.write(UInt16(names.count))
                    names.write(bytes: name.lengthPrefixed)
                } else {
                    references.write(UInt16(0xFFFF))
                }
                // resChanged is the Resource Manager's own, never written.
                references.write(item.resource.attributes.subtracting(.changed).rawValue)
                references.write(UInt8(data.count >> 16))
                references.write(UInt16(data.count & 0xFFFF))
                references.write(UInt32(0))
                data.write(UInt32(item.bytes.count))
                data.write(bytes: item.bytes)
            }
        }

        let mapOffset = dataOffset + data.count
        let typeListOffset = 28
        let nameListOffset = typeListOffset + typeList(types, references).count
        guard nameListOffset <= 0xFFFF else { throw .addResourceFailed }
        var map = BigEndianWriter()
        let mapLength = nameListOffset + names.count
        for value in [UInt32(dataOffset), UInt32(mapOffset), UInt32(data.count), UInt32(mapLength)] { map.write(value) }
        map.write(UInt32(0))   // the next map's handle
        map.write(UInt16(0))   // the file's reference number
        map.write(attributes.subtracting(.changed).rawValue)
        map.write(UInt16(typeListOffset))
        map.write(UInt16(nameListOffset))
        map.write(bytes: typeList(types, references))
        map.write(bytes: names.bytes)

        var fork = BigEndianWriter(capacity: mapOffset + map.count)
        for value in [UInt32(dataOffset), UInt32(mapOffset), UInt32(data.count), UInt32(mapLength)] { fork.write(value) }
        var reserved = Array(reservedHeader.prefix(dataOffset - 16))
        reserved += [UInt8](repeating: 0, count: dataOffset - 16 - reserved.count)
        fork.write(bytes: reserved)
        fork.write(bytes: data.bytes)
        fork.write(bytes: map.bytes)
        return fork.bytes
    }

    private static func typeList(_ types: BigEndianWriter, _ references: BigEndianWriter) -> [UInt8] {
        types.bytes + references.bytes
    }

    /// An empty resource fork, as FSCreateResFile makes.
    public static var emptyFork: [UInt8] {
        (try? write([])) ?? []
    }
}
