// Forks: a file's data fork, read and written through its descriptor, and
// its resource fork, wherever the file system keeps one:
//
// - "._name", an AppleDouble file, as macOS and archivers leave it;
// - "name.rsrc", raw or AppleDouble, as Pomme's games keep it;
// - on macOS, the file's own resource fork.
//
// A resource fork is read whole when it opens and written back where it came
// from when it is flushed or closed; a file with none gets "._name". Each
// fork keeps its own mark, and reads and writes at an offset, so that a read
// on another thread (PBReadAsync's) doesn't move another's.

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

public enum ForkKind: Hashable, Sendable {
    case data
    case resource
}

/// How a fork is opened: fsCurPerm, fsRdPerm, fsWrPerm, fsRdWrPerm.
public enum ForkPermission: Hashable, Sendable {
    /// Reading and writing if the file allows it, else reading.
    case current
    case read
    case write
    case readWrite

    /// The File Manager's permission byte; fsRdWrShPerm (4) is readWrite.
    public init(_ value: Int8) {
        switch value {
        case 1: self = .read
        case 2: self = .write
        case 3, 4: self = .readWrite
        default: self = .current
        }
    }
}

/// Where a read, write or seek starts: fsAtMark, fsFromStart, fsFromLEOF,
/// fsFromMark.
public enum ForkPosition: Hashable, Sendable {
    case start(Int64)
    case end(Int64)
    case mark(Int64)

    /// The File Manager's positioning mode and offset; fsAtMark is the mark.
    public init(mode: UInt16, offset: Int64) {
        switch mode & 3 {
        case 0: self = .mark(0)
        case 1: self = .start(offset)
        case 2: self = .end(offset)
        default: self = .mark(offset)
        }
    }
}

/// An open fork.
public final class Fork: Sendable {

    public let kind: ForkKind

    /// The file's path.
    public let path: String

    public let canRead: Bool

    public let canWrite: Bool

    private enum Storage {
        case descriptor(FileDescriptor)
        case memory(ResourceForkStore)
    }

    private struct State {
        var storage: Storage
        var mark: Int64 = 0
        var dirty = false
        var closed = false
    }

    private let state: Mutex<State>

    /// Opens a file's fork: fnfErr if the file isn't there, permErr if it
    /// can't be opened as asked.
    public init(path: String, kind: ForkKind, permission: ForkPermission) throws(MacError) {
        guard let item = ItemStatus(path: path) else { throw .fileNotFound }
        guard !item.isDirectory else { throw .fileNotFound }
        self.path = path
        self.kind = kind
        var canRead = permission != .write
        var canWrite = permission != .read
        switch kind {
        case .data:
            let mode: FileDescriptor.AccessMode = canRead ? (canWrite ? .readWrite : .readOnly) : .writeOnly
            do {
                state = Mutex(State(storage: .descriptor(try FileDescriptor.open(FilePath(path), mode))))
            } catch let error as Errno {
                // fsCurPerm: as much as is allowed.
                guard permission == .current, error == .permissionDenied || error == .readOnlyFileSystem,
                      let file = try? FileDescriptor.open(FilePath(path), .readOnly) else { throw MacError(error) }
                canWrite = false
                state = Mutex(State(storage: .descriptor(file)))
            } catch {
                throw .io
            }
        case .resource:
            let store = ResourceForkStore.locate(for: path) ?? ResourceForkStore(path: path)
            if canWrite, access(Paths.parent(of: store.storePath), W_OK) != 0 {
                guard permission == .current else { throw .permission }
                canWrite = false
            }
            if !canRead && !canWrite { canRead = true }
            state = Mutex(State(storage: .memory(store)))
        }
        self.canRead = canRead
        self.canWrite = canWrite
    }

    deinit {
        try? close()
    }

    /// Where the next read or write starts.
    public var position: Int64 { state.withLock { $0.mark } }

    /// The fork's length.
    public var size: Int64 {
        state.withLock { state in
            switch state.storage {
            case .descriptor(let file): return ItemStatus(descriptor: file.rawValue)?.size ?? 0
            case .memory(let store): return Int64(store.bytes.count)
            }
        }
    }

    /// Moves the mark: posErr before the start. The mark may go past the
    /// end, where a write extends the fork.
    @discardableResult
    public func seek(_ position: ForkPosition) throws(MacError) -> Int64 {
        let size = self.size
        return try state.withLock { state throws(MacError) in
            let mark: Int64
            switch position {
            case .start(let offset): mark = offset
            case .end(let offset): mark = size + offset
            case .mark(let offset): mark = state.mark + offset
            }
            guard mark >= 0 else { throw .position }
            state.mark = mark
            return mark
        }
    }

    /// Reads from the mark, or from `position` first, as much as there is
    /// up to the buffer's size; the mark moves past what was read. A count
    /// less than the buffer's means the end came first.
    public func read(into buffer: UnsafeMutableRawBufferPointer, from position: ForkPosition? = nil) throws(MacError) -> Int {
        guard canRead else { throw .permission }
        if let position { try seek(position) }
        return try state.withLock { state throws(MacError) in
            guard !state.closed else { throw .fileNotOpen }
            var count = 0
            switch state.storage {
            case .descriptor(let file):
                while count < buffer.count {
                    let slice = UnsafeMutableRawBufferPointer(rebasing: buffer[count...])
                    let read: Int
                    do {
                        read = try file.read(fromAbsoluteOffset: state.mark + Int64(count), into: slice, retryOnInterrupt: true)
                    } catch {
                        state.mark += Int64(count)
                        throw .io
                    }
                    if read == 0 { break }
                    count += read
                }
            case .memory(let store):
                let start = Int(clamping: min(state.mark, Int64(store.bytes.count)))
                count = min(buffer.count, store.bytes.count - start)
                if count > 0 {
                    store.bytes.withUnsafeBytes { buffer.baseAddress!.copyMemory(from: $0.baseAddress! + start, byteCount: count) }
                }
            }
            state.mark += Int64(count)
            return count
        }
    }

    /// Writes at the mark, or at `position` first; the mark moves past what
    /// was written.
    @discardableResult
    public func write(_ bytes: UnsafeRawBufferPointer, at position: ForkPosition? = nil) throws(MacError) -> Int {
        guard canWrite else { throw .writePermission }
        if let position { try seek(position) }
        return try state.withLock { state throws(MacError) in
            guard !state.closed else { throw .fileNotOpen }
            switch state.storage {
            case .descriptor(let file):
                var count = 0
                while count < bytes.count {
                    do {
                        count += try file.write(
                            toAbsoluteOffset: state.mark + Int64(count), UnsafeRawBufferPointer(rebasing: bytes[count...]), retryOnInterrupt: true
                        )
                    } catch let error as Errno {
                        state.mark += Int64(count)
                        throw MacError(error)
                    } catch {
                        throw .io
                    }
                }
            case .memory(var store):
                let start = Int(clamping: state.mark)
                if store.bytes.count < start + bytes.count {
                    store.bytes += [UInt8](repeating: 0, count: start + bytes.count - store.bytes.count)
                }
                store.bytes.withUnsafeMutableBytes { $0.baseAddress!.advanced(by: start).copyMemory(from: bytes.baseAddress!, byteCount: bytes.count) }
                state.storage = .memory(store)
                state.dirty = true
            }
            state.mark += Int64(bytes.count)
            return bytes.count
        }
    }

    /// Sets the fork's length; the mark stays where it is.
    public func setSize(_ size: Int64) throws(MacError) {
        guard canWrite else { throw .writePermission }
        guard size >= 0 else { throw .position }
        try state.withLock { state throws(MacError) in
            switch state.storage {
            case .descriptor(let file):
                guard ftruncate(file.rawValue, off_t(truncatingIfNeeded: size)) == 0 else { throw MacError(errno: errno) }
            case .memory(var store):
                let size = Int(clamping: size)
                if size < store.bytes.count {
                    store.bytes.removeLast(store.bytes.count - size)
                } else {
                    store.bytes += [UInt8](repeating: 0, count: size - store.bytes.count)
                }
                state.storage = .memory(store)
                state.dirty = true
            }
        }
    }

    /// Space for the fork to grow into: Linux's file systems give it as it
    /// is written, so all of it is taken as allocated.
    public func allocate(_ count: UInt64) throws(MacError) -> UInt64 {
        guard canWrite else { throw .writePermission }
        return count
    }

    /// Writes the fork out: a resource fork to where it is kept.
    public func flush() throws(MacError) {
        try state.withLock { state throws(MacError) in
            switch state.storage {
            case .descriptor(let file):
                fsync(file.rawValue)
            case .memory(let store):
                guard state.dirty else { return }
                try store.write()
                state.dirty = false
            }
        }
    }

    /// Flushes and closes the fork; closing it again does nothing.
    public func close() throws(MacError) {
        let storage: Storage? = state.withLock { state in
            guard !state.closed else { return nil }
            state.closed = true
            return state.storage
        }
        switch storage {
        case .descriptor(let file):
            try? file.close()
        case .memory(let store):
            if state.withLock({ $0.dirty }) { try store.write() }
        case nil:
            break
        }
    }
}

/// Where a file's resource fork is kept, and its bytes.
struct ResourceForkStore {

    enum Kind {
        /// "._name".
        case appleDouble
        /// "name.rsrc", the fork's bytes alone.
        case rsrcFile
        /// "name.rsrc" as an AppleDouble or AppleSingle file.
        case rsrcAppleDouble
        /// macOS's own: "name/..namedfork/rsrc".
        case namedFork
    }

    var kind: Kind
    var storePath: String
    var bytes: [UInt8]

    /// A fork that isn't anywhere yet: "._name" when it is written.
    init(path: String) {
        kind = .appleDouble
        storePath = FileSystem.appleDoublePath(of: path)
        bytes = []
    }

    init(kind: Kind, storePath: String, bytes: [UInt8]) {
        self.kind = kind
        self.storePath = storePath
        self.bytes = bytes
    }

    /// The file's resource fork, if it has one.
    static func locate(for path: String) -> ResourceForkStore? {
        let double = FileSystem.appleDoublePath(of: path)
        if let bytes = POSIX.readFile(double), let file = try? AppleDouble(bytes: bytes), let fork = file.resourceFork {
            return ResourceForkStore(kind: .appleDouble, storePath: double, bytes: fork)
        }
        let rsrc = path + ".rsrc"
        if let bytes = POSIX.readFile(rsrc) {
            if AppleDouble.isAppleDouble(bytes) {
                if let fork = (try? AppleDouble(bytes: bytes))?.resourceFork {
                    return ResourceForkStore(kind: .rsrcAppleDouble, storePath: rsrc, bytes: fork)
                }
            } else {
                return ResourceForkStore(kind: .rsrcFile, storePath: rsrc, bytes: bytes)
            }
        }
        #if canImport(Darwin)
        let named = path + "/..namedfork/rsrc"
        if let bytes = POSIX.readFile(named), !bytes.isEmpty {
            return ResourceForkStore(kind: .namedFork, storePath: named, bytes: bytes)
        }
        #endif
        return nil
    }

    /// Writes the fork back where it came from, keeping an AppleDouble
    /// file's other entries.
    func write() throws(MacError) {
        switch kind {
        case .rsrcFile:
            try POSIX.writeFile(storePath, bytes)
        case .namedFork:
            // Written in place: the fork is part of the file.
            do {
                let file = try FileDescriptor.open(FilePath(storePath), .writeOnly, options: [.create, .truncate], permissions: .ownerReadWrite)
                try file.closeAfter { _ = try bytes.withUnsafeBytes { try file.writeAll($0) } }
            } catch let error as Errno {
                throw MacError(error)
            } catch {
                throw .io
            }
        case .appleDouble, .rsrcAppleDouble:
            var file = POSIX.readFile(storePath).flatMap { try? AppleDouble(bytes: $0) } ?? AppleDouble()
            file.resourceFork = bytes
            try POSIX.writeFile(storePath, file.bytes)
        }
    }
}

// MARK: - Reference numbers

/// A fork opened by reference number.
struct OpenFork {
    var fork: Fork
}

public extension FileSystem {

    /// The most forks open at once.
    static var maximumOpenForks: Int { 512 }

    /// Opens a fork and gives it a reference number, from 2 up, as the File
    /// Manager's are small positive numbers.
    func open(_ path: String, fork kind: ForkKind, permission: ForkPermission) throws(MacError) -> (reference: Int16, fork: Fork) {
        let fork = try Fork(path: path, kind: kind, permission: permission)
        let reference: Int16? = state.withLock { state in
            for number in 2 ..< Int16(Self.maximumOpenForks) where state.forks[number] == nil {
                state.forks[number] = OpenFork(fork: fork)
                return number
            }
            return nil
        }
        guard let reference else {
            try? fork.close()
            throw .tooManyFilesOpen
        }
        return (reference, fork)
    }

    /// The fork a reference number names, if it is open.
    func fork(_ reference: Int16) -> Fork? {
        state.withLock { $0.forks[reference]?.fork }
    }

    /// Closes a fork by its reference number: rfNumErr if none is open.
    func close(_ reference: Int16) throws(MacError) {
        guard let open = state.withLock({ $0.forks.removeValue(forKey: reference) }) else { throw .referenceNumber }
        try open.fork.close()
    }

    /// The forks open now, by reference number.
    var openForks: [Int16: Fork] {
        state.withLock { $0.forks.mapValues(\.fork) }
    }
}
