// FSSpecs: an item named by its volume, its folder's ID and its name, as
// the File Manager named items before FSRefs. Names are MacRoman, at most
// 63 bytes, and HFS parts paths with ':' where POSIX parts them with '/'.

import GraphiteBase

/// A folder's ID: its inode, except that the root is 2 and the root's
/// parent 1, as HFS numbers them.
public struct DirectoryID: RawRepresentable, Hashable, Sendable {

    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// fsRtParID: the root's parent, which the volume's own spec names.
    public static var rootParent: DirectoryID { DirectoryID(1) }

    /// fsRtDirID: the root folder.
    public static var root: DirectoryID { DirectoryID(2) }
}

/// An item by its volume, folder and name.
public struct FileSpec: Hashable, Sendable {

    public var volume: Int16

    public var parent: DirectoryID

    /// At most 63 bytes.
    public var name: PascalString

    public init(volume: Int16, parent: DirectoryID, name: PascalString) {
        self.volume = volume
        self.parent = parent
        self.name = name
    }
}

/// Names as HFS has them and as POSIX does.
public enum FileNames {

    /// The most bytes in an FSSpec's name.
    public static var specLength: Int { 63 }

    /// A POSIX name as HFS shows it: '/' for ':', which HFS can't have.
    public static func hfs(_ name: String) -> String {
        String(name.map { $0 == ":" ? "/" : $0 })
    }

    /// An HFS name as POSIX keeps it: ':' for '/'.
    public static func posix(_ name: String) -> String {
        String(name.map { $0 == "/" ? ":" : $0 })
    }

    /// A POSIX name for an FSSpec: MacRoman, or its UTF-8 where it isn't
    /// all MacRoman. A name longer than 63 bytes is shortened and ends in
    /// '#' and the item's ID in hex, as the File Manager mangled long names
    /// for FSSpecs, and `lookUp` finds it again by that ID.
    public static func specName(_ name: String, id: UInt32) -> PascalString {
        let shown = hfs(name)
        let bytes = MacRoman.encode(shown) ?? Array(shown.utf8)
        guard bytes.count > specLength else { return PascalString(bytes: bytes) }
        let suffix = Array(("#" + String(id, radix: 16, uppercase: true)).utf8)
        var kept = Array(bytes.prefix(specLength - suffix.count))
        // Not partway through a UTF-8 character.
        if MacRoman.encode(shown) == nil {
            while let last = kept.last, last & 0xC0 == 0x80 { kept.removeLast() }
            if let last = kept.last, last >= 0xC0 { kept.removeLast() }
        }
        return PascalString(bytes: kept + suffix)
    }

    /// The POSIX names an FSSpec's name can be: its MacRoman text, and its
    /// bytes as UTF-8 when they are.
    static func candidates(_ name: PascalString) -> [String] {
        var names = [posix(name.string)]
        if let utf8 = String(validating: name.bytes, as: UTF8.self), utf8 != name.string {
            names.append(posix(utf8))
        }
        return names
    }

    /// The ID a mangled name ends with: "Long name…#1A2B".
    static func mangledID(_ name: String) -> UInt32? {
        guard let hash = name.lastIndex(of: "#") else { return nil }
        let digits = name[name.index(after: hash)...]
        guard !digits.isEmpty, digits.count <= 8 else { return nil }
        return UInt32(digits, radix: 16)
    }
}

/// Colon paths, as the File Manager's calls took in a name: "a:b" from the
/// folder, ":a:b" too, "::a" from the folder's parent, "Volume:a:b" from the
/// volume's root.
public enum ColonPath {

    /// The POSIX path a name gives, from a folder; the folder itself for an
    /// empty one.
    public static func join(folder: String, name: PascalString) -> String {
        let text = name.string
        guard !text.isEmpty else { return folder }
        var folder = folder
        var rest = Substring(text)
        if let colon = text.firstIndex(of: ":"), colon != text.startIndex {
            // "Volume:…": the one volume is the root.
            folder = "/"
            rest = text[text.index(after: colon)...]
        } else if rest.first == ":" {
            rest = rest.dropFirst()
        }
        var parts: [String] = []
        var name = ""
        var colons = 0
        func endName() {
            if !name.isEmpty {
                parts.append(FileNames.posix(name))
                name = ""
            }
        }
        for character in rest {
            if character == ":" {
                colons += 1
                continue
            }
            if colons > 0 {
                // Each ':' after the first in a row goes up a folder; at the
                // start each does.
                let ups = name.isEmpty && parts.isEmpty ? colons : colons - 1
                endName()
                parts.append(contentsOf: repeatElement("..", count: ups))
                colons = 0
            }
            name.append(character)
        }
        endName()
        if colons > 0 {
            parts.append(contentsOf: repeatElement("..", count: parts.isEmpty ? colons : colons - 1))
        }
        var path = folder
        for part in parts { path = Paths.appending(part, to: path) }
        return path
    }
}
