// What the File Manager asks of the file system underneath: an item's
// status, a folder's names, and the result code for an errno.

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import GraphiteBase
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// What stat tells of an item.
struct ItemStatus {

    var device: UInt64
    var inode: UInt64
    var mode: UInt32
    var size: Int64
    /// Bytes the item takes on disk.
    var allocated: Int64
    /// Unix seconds.
    var modified: Int64
    var changed: Int64
    var accessed: Int64
    /// When the item was made, where the file system keeps it; else when its
    /// status last changed, as Perry's C took it.
    var created: Int64

    var isDirectory: Bool { mode & UInt32(S_IFMT) == UInt32(S_IFDIR) }

    var isRegularFile: Bool { mode & UInt32(S_IFMT) == UInt32(S_IFREG) }

    /// The item at a path, following symbolic links.
    init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        self.init(info)
    }

    init?(descriptor: Int32) {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return nil }
        self.init(info)
    }

    private init(_ info: stat) {
        device = UInt64(truncatingIfNeeded: info.st_dev)
        inode = UInt64(truncatingIfNeeded: info.st_ino)
        mode = UInt32(truncatingIfNeeded: info.st_mode)
        size = Int64(info.st_size)
        allocated = Int64(info.st_blocks) * 512
        #if canImport(Darwin)
        modified = Int64(info.st_mtimespec.tv_sec)
        changed = Int64(info.st_ctimespec.tv_sec)
        accessed = Int64(info.st_atimespec.tv_sec)
        created = Int64(info.st_birthtimespec.tv_sec)
        #else
        modified = Int64(info.st_mtim.tv_sec)
        changed = Int64(info.st_ctim.tv_sec)
        accessed = Int64(info.st_atim.tv_sec)
        created = changed
        #endif
    }

    static func exists(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0
    }
}

enum POSIX {

    /// The names in a folder, without "." and "..".
    static func names(inFolder path: String) -> [String]? {
        guard let directory = opendir(path) else { return nil }
        defer { closedir(directory) }
        var names: [String] = []
        while let entry = readdir(directory) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            if name != "." && name != ".." { names.append(name) }
        }
        return names
    }

    /// The path a path resolves to: symbolic links followed, "." and ".."
    /// gone.
    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static var workingDirectory: String {
        guard let path = getcwd(nil, 0) else { return "/" }
        defer { free(path) }
        return String(cString: path)
    }

    static func environment(_ name: String) -> String? {
        guard let value = getenv(name), value.pointee != 0 else { return nil }
        return String(cString: value)
    }

    static var errorNumber: Int32 { errno }

    /// mkdir -p.
    static func makeFolders(_ path: String) -> Bool {
        if ItemStatus(path: path)?.isDirectory == true { return true }
        let parent = Paths.parent(of: path)
        if parent != path, !makeFolders(parent) { return false }
        return mkdir(path, 0o755) == 0 || errno == EEXIST
    }

    /// The whole of a file, or nil if it can't be read.
    static func readFile(_ path: String) -> [UInt8]? {
        guard let file = try? FileDescriptor.open(FilePath(path), .readOnly) else { return nil }
        return try? file.closeAfter {
            var bytes: [UInt8] = []
            var chunk = [UInt8](repeating: 0, count: 65536)
            while true {
                let count = try chunk.withUnsafeMutableBytes { try file.read(into: $0) }
                if count == 0 { return bytes }
                bytes.append(contentsOf: chunk[0 ..< count])
            }
        }
    }

    /// Writes a whole file, through a temporary file beside it so that a
    /// failed write leaves the old one.
    static func writeFile(_ path: String, _ bytes: [UInt8]) throws(MacError) {
        let temporary = Paths.appending(".graphite-\(getpid())-" + Paths.name(of: path), to: Paths.parent(of: path))
        do {
            let file = try FileDescriptor.open(
                FilePath(temporary), .writeOnly, options: [.create, .truncate], permissions: [.ownerReadWrite, .groupRead, .otherRead]
            )
            try file.closeAfter { _ = try bytes.withUnsafeBytes { try file.writeAll($0) } }
            guard rename(temporary, path) == 0 else { throw Errno(rawValue: errno) }
        } catch let error as Errno {
            unlink(temporary)
            throw MacError(error)
        } catch {
            unlink(temporary)
            throw MacError.io
        }
    }
}

/// POSIX paths, taken apart without the file system.
enum Paths {

    /// An absolute path without ".", "..", repeated or trailing slashes.
    static func standardized(_ path: String) -> String {
        var path = FilePath(path)
        if !path.isAbsolute { path = FilePath("/").pushing(path) }
        return path.lexicallyNormalized().string
    }

    /// The folder an item is in; the root is its own.
    static func parent(of path: String) -> String {
        let path = FilePath(path)
        guard path.root == nil || !path.components.isEmpty else { return path.string }
        let parent = path.removingLastComponent()
        return parent.isEmpty ? "." : parent.string
    }

    /// The last name in a path.
    static func name(of path: String) -> String {
        FilePath(path).lastComponent?.string ?? ""
    }

    static func appending(_ name: String, to folder: String) -> String {
        folder == "/" ? "/" + name : folder + "/" + name
    }
}

public extension MacError {

    /// The File Manager's code for an errno.
    init(_ errno: Errno) {
        switch errno {
        case .noSuchFileOrDirectory: self = .fileNotFound
        case .notDirectory: self = .directoryNotFound
        case .fileExists: self = .duplicateFileName
        case .permissionDenied, .notPermitted: self = .permission
        case .readOnlyFileSystem: self = .writeProtected
        case .noSpace: self = .diskFull
        case .tooManyOpenFiles, .tooManyOpenFilesInSystem: self = .tooManyFilesOpen
        case .resourceBusy, .directoryNotEmpty: self = .fileBusy
        case .fileNameTooLong: self = .badName
        case .badFileDescriptor: self = .writePermission
        default: self = .io
        }
    }

    init(errno: Int32) {
        self.init(Errno(rawValue: errno))
    }
}

