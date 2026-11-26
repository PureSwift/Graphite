// AppleDouble and AppleSingle files (RFC 1740): how a Mac file's resource
// fork and Finder info are kept on a file system without them. macOS and
// archivers write a file's as "._name" beside it; Pomme's games keep
// "name.rsrc". Entries Graphite doesn't read are kept as they are when it
// writes the file again, as are the bytes after the Finder info's 32 that
// macOS keeps extended attributes in.
//
// Reading a resource fork from "name.rsrc" follows Pomme's
// Files/HostVolume.cpp (ADFJumpToResourceFork):
// Copyright (c) 2020 Iliyas Jorio. MIT License.

import GraphiteBase

/// An AppleDouble or AppleSingle file's entries.
public struct AppleDouble: Hashable, Sendable {

    /// An entry's ID.
    public struct EntryID: RawRepresentable, Hashable, Sendable {
        public var rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static var dataFork: EntryID { EntryID(rawValue: 1) }
        public static var resourceFork: EntryID { EntryID(rawValue: 2) }
        public static var realName: EntryID { EntryID(rawValue: 3) }
        public static var comment: EntryID { EntryID(rawValue: 4) }
        public static var fileDates: EntryID { EntryID(rawValue: 8) }
        public static var finderInfo: EntryID { EntryID(rawValue: 9) }
    }

    public struct Entry: Hashable, Sendable {
        public var id: EntryID
        public var bytes: [UInt8]

        public init(id: EntryID, bytes: [UInt8]) {
            self.id = id
            self.bytes = bytes
        }
    }

    public static var appleSingleMagic: UInt32 { 0x0005_1600 }
    public static var appleDoubleMagic: UInt32 { 0x0005_1607 }

    /// AppleSingle keeps the data fork too; AppleDouble doesn't.
    public var isAppleSingle: Bool

    /// In the order they're written.
    public var entries: [Entry]

    public init(isAppleSingle: Bool = false, entries: [Entry] = []) {
        self.isAppleSingle = isAppleSingle
        self.entries = entries
    }

    /// Whether bytes start as an AppleDouble or AppleSingle file does.
    public static func isAppleDouble(_ bytes: [UInt8]) -> Bool {
        guard let magic = try? BigEndianReader(bytes).peek(UInt32.self, at: 0) else { return false }
        return magic == appleDoubleMagic || magic == appleSingleMagic
    }

    /// Throws for bytes that aren't one, or an entry past their end.
    public init(bytes: [UInt8]) throws(MacError) {
        do {
            var reader = BigEndianReader(bytes)
            let magic = try reader.read(UInt32.self)
            guard magic == Self.appleDoubleMagic || magic == Self.appleSingleMagic else { throw MacError.parameter }
            isAppleSingle = magic == Self.appleSingleMagic
            try reader.skip(4 + 16)   // version, filler
            let count = try reader.read(UInt16.self)
            entries = []
            for _ in 0 ..< count {
                let id = try reader.read(UInt32.self)
                let offset = Int(try reader.read(UInt32.self))
                let length = Int(try reader.read(UInt32.self))
                let entry = try reader.subreader(at: offset, count: length)
                entries.append(Entry(id: EntryID(rawValue: id), bytes: entry.bytes))
            }
        } catch let error as MacError {
            throw error
        } catch {
            throw MacError.parameter
        }
    }

    /// The file: version 2, entries after the header in their order.
    public var bytes: [UInt8] {
        var writer = BigEndianWriter()
        writer.write(isAppleSingle ? Self.appleSingleMagic : Self.appleDoubleMagic)
        writer.write(UInt32(0x0002_0000))
        writer.writeZeros(16)
        writer.write(UInt16(entries.count))
        var offset = 26 + 12 * entries.count
        for entry in entries {
            writer.write(entry.id.rawValue)
            writer.write(UInt32(offset))
            writer.write(UInt32(entry.bytes.count))
            offset += entry.bytes.count
        }
        for entry in entries { writer.write(bytes: entry.bytes) }
        return writer.bytes
    }

    public subscript(id: EntryID) -> [UInt8]? {
        get { entries.first { $0.id == id }?.bytes }
        set {
            guard let newValue else {
                entries.removeAll { $0.id == id }
                return
            }
            if let index = entries.firstIndex(where: { $0.id == id }) {
                entries[index].bytes = newValue
            } else if id == .finderInfo, let fork = entries.firstIndex(where: { $0.id == .resourceFork }) {
                // Finder info before the resource fork, as macOS writes them,
                // so that the fork can grow at the end.
                entries.insert(Entry(id: id, bytes: newValue), at: fork)
            } else {
                entries.append(Entry(id: id, bytes: newValue))
            }
        }
    }

    public var resourceFork: [UInt8]? {
        get { self[.resourceFork] }
        set { self[.resourceFork] = newValue }
    }

    /// The Finder info's first 32 bytes, FInfo or DInfo and their extended
    /// halves.
    public var finderInfo: FinderInfo? {
        get { self[.finderInfo].map { FinderInfo(bytes: $0) } }
        set {
            guard let newValue else {
                self[.finderInfo] = nil
                return
            }
            var bytes = self[.finderInfo] ?? []
            if bytes.count < 32 { bytes += [UInt8](repeating: 0, count: 32 - bytes.count) }
            bytes.replaceSubrange(0 ..< 32, with: newValue.bytes)
            self[.finderInfo] = bytes
        }
    }
}

/// The Finder's information about an item: FInfo and FXInfo for a file,
/// DInfo and DXInfo for a folder, 32 bytes. Both keep their flags at 8 and
/// their location at 10.
public struct FinderInfo: Hashable, Sendable {

    /// Always 32.
    public private(set) var bytes: [UInt8]

    public init() {
        bytes = [UInt8](repeating: 0, count: 32)
    }

    /// The first 32 bytes, zeros after fewer.
    public init(bytes: some Collection<UInt8>) {
        var all = Array(bytes.prefix(32))
        if all.count < 32 { all += [UInt8](repeating: 0, count: 32 - all.count) }
        self.bytes = all
    }

    public init(type: FourCharCode, creator: FourCharCode, flags: UInt16 = 0) {
        self.init()
        self.type = type
        self.creator = creator
        self.flags = flags
    }

    /// A file's type.
    public var type: FourCharCode {
        get { FourCharCode(word(at: 0)) }
        set { setWord(newValue.rawValue, at: 0) }
    }

    /// A file's creator.
    public var creator: FourCharCode {
        get { FourCharCode(word(at: 4)) }
        set { setWord(newValue.rawValue, at: 4) }
    }

    /// kIsAlias, kHasCustomIcon, kIsInvisible, kHasBundle and the others.
    public var flags: UInt16 {
        get { UInt16(bytes[8]) << 8 | UInt16(bytes[9]) }
        set {
            bytes[8] = UInt8(newValue >> 8)
            bytes[9] = UInt8(newValue & 0xFF)
        }
    }

    /// Where the item is in its folder's window.
    public var location: Point {
        get { Point(v: Int16(bitPattern: UInt16(bytes[10]) << 8 | UInt16(bytes[11])), h: Int16(bitPattern: UInt16(bytes[12]) << 8 | UInt16(bytes[13]))) }
        set {
            let v = UInt16(bitPattern: newValue.v), h = UInt16(bitPattern: newValue.h)
            bytes[10] = UInt8(v >> 8)
            bytes[11] = UInt8(v & 0xFF)
            bytes[12] = UInt8(h >> 8)
            bytes[13] = UInt8(h & 0xFF)
        }
    }

    public var isEmpty: Bool { bytes.allSatisfy { $0 == 0 } }

    /// kIsAlias.
    public static var isAliasFlag: UInt16 { 0x8000 }

    /// kIsInvisible.
    public static var isInvisibleFlag: UInt16 { 0x4000 }

    private func word(at offset: Int) -> UInt32 {
        bytes[offset ..< offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }

    private mutating func setWord(_ value: UInt32, at offset: Int) {
        for index in 0 ..< 4 { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (24 - 8 * index)) }
    }
}
