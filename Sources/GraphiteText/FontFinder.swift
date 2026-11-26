// Finding installed fonts by family name: the folders fonts are kept in, on
// macOS and on Linux (XDG's too), read once with FreeType for each file's
// family. Give `lookUp` to a FontRegistry.

#if FreeType
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import Synchronization

public final class FontFinder: Sendable {

    /// A font file and the face in it.
    public struct Entry: Hashable, Sendable {
        public var path: String
        public var index: Int
        public var family: String
        public var style: String
    }

    private let folders: [String]
    private let entries = Mutex<[Entry]?>(nil)

    /// Looks in the standard folders, and `extra` ones first.
    public init(extraFolders: [String] = []) {
        let home = getenv("HOME").map { String(cString: $0) } ?? "/"
        var data = getenv("XDG_DATA_HOME").map { String(cString: $0) } ?? home + "/.local/share"
        if data.isEmpty { data = home + "/.local/share" }
        folders = extraFolders + [
            data + "/fonts", home + "/.fonts", home + "/Library/Fonts",
            "/Library/Fonts", "/System/Library/Fonts", "/System/Library/Fonts/Supplemental",
            "/usr/local/share/fonts", "/usr/share/fonts",
        ]
    }

    /// Every face found, scanned on first use.
    public var fonts: [Entry] {
        entries.withLock { cached in
            if let cached { return cached }
            var found: [Entry] = []
            // A folder may be inside another (Supplemental is in Fonts), so
            // a file is read once, whichever folder reaches it first.
            var seen = Set<String>()
            for folder in folders { Self.scan(folder, depth: 0, into: &found, seen: &seen) }
            cached = found
            return found
        }
    }

    /// A face of a family, in any case: its regular style where there is
    /// one.
    public func face(family: String) -> FreeTypeFace? {
        let wanted = family.lowercased()
        let matches = fonts.filter { $0.family.lowercased() == wanted }
        guard let entry = matches.first(where: { ["regular", "roman", "book", "medium"].contains($0.style.lowercased()) }) ?? matches.first else { return nil }
        return try? FreeTypeFace(path: entry.path, index: entry.index)
    }

    /// For FontRegistry's `lookUp`.
    public var lookUp: @Sendable (String) -> (any FontFace)? {
        { [self] name in face(family: name) }
    }

    private static let extensions: Set<String> = ["ttf", "otf", "ttc", "otc", "pfb", "dfont"]

    private static func scan(_ folder: String, depth: Int, into found: inout [Entry], seen: inout Set<String>) {
        guard depth < 4, let directory = opendir(folder) else { return }
        defer { closedir(directory) }
        var names: [(String, Bool)] = []
        while let entry = readdir(directory) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            guard !name.hasPrefix(".") else { continue }
            names.append((name, entry.pointee.d_type == UInt8(DT_DIR)))
        }
        for (name, isDirectory) in names.sorted(by: { $0.0 < $1.0 }) {
            let path = folder + "/" + name
            if isDirectory {
                scan(path, depth: depth + 1, into: &found, seen: &seen)
            } else if let dot = name.lastIndex(of: "."), extensions.contains(name[name.index(after: dot)...].lowercased()) {
                guard seen.insert(path).inserted else { continue }
                guard let first = try? FreeTypeFace(path: path) else { continue }
                found.append(Entry(path: path, index: 0, family: first.familyName, style: first.styleName))
                // A collection's other faces.
                for index in 1 ..< first.faceCount {
                    guard let next = try? FreeTypeFace(path: path, index: index) else { continue }
                    found.append(Entry(path: path, index: index, family: next.familyName, style: next.styleName))
                }
            }
        }
    }
}
#endif
