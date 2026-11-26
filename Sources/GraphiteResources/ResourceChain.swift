// The Resource Manager's chain of open files: the last opened first, and a
// current file searches start from. Get searches from the current file back
// to the first opened; Get1 the current file alone. A file's reference
// number is its fork's, from the File Manager, as the Toolbox's were.

import GraphiteBase
import GraphiteFiles

public final class ResourceChain {

    /// A file open in the chain.
    public struct OpenFile {
        public var reference: Int16
        public var file: ResourceFile
    }

    /// The last opened first.
    public private(set) var files: [OpenFile] = []

    /// CurResFile: where searches start; 0 when none is open.
    public private(set) var current: Int16 = 0

    /// SetResLoad: whether Get reads a resource's bytes or only finds it.
    /// The layer that gives out handles decides what an unloaded one is.
    public var loadsResources = true

    /// Where files are opened and their reference numbers come from.
    public let fileSystem: FileSystem

    /// The next reference number for a file made from bytes alone, below
    /// the File Manager's so as never to meet them.
    private var nextBytesReference: Int16 = -2

    public init(fileSystem: FileSystem) {
        self.fileSystem = fileSystem
    }

    // MARK: Opening and closing

    /// FSOpenResFile and FSOpenResourceFile: a file's resource fork, or its
    /// data fork as ".rsrc" files keep resources, made the current file.
    /// Opening a file open already gives its reference number again.
    @discardableResult
    public func open(_ path: String, fork kind: ForkKind = .resource, permission: ForkPermission = .current) throws(MacError) -> Int16 {
        for open in files where open.file.fork?.path == path && open.file.fork?.kind == kind {
            current = open.reference
            return open.reference
        }
        let (reference, fork) = try fileSystem.open(path, fork: kind, permission: permission)
        do {
            let file = try ResourceFile(fork: fork)
            insert(OpenFile(reference: reference, file: file))
            return reference
        } catch {
            try? fileSystem.close(reference)
            throw error
        }
    }

    /// A file of resources from bytes, which can't be written back.
    @discardableResult
    public func open(bytes: [UInt8]) throws(MacError) -> Int16 {
        let file = try ResourceFile(bytes: bytes)
        let reference = nextBytesReference
        nextBytesReference -= 1
        insert(OpenFile(reference: reference, file: file))
        return reference
    }

    private func insert(_ open: OpenFile) {
        files.insert(open, at: 0)
        current = open.reference
    }

    /// FSCreateResFile: an empty resource fork for a file that has none,
    /// the file made first if it isn't there.
    public func create(_ path: String, fork kind: ForkKind = .resource, finderInfo: FinderInfo? = nil) throws(MacError) {
        if fileSystem.lookUp(path) == nil {
            try fileSystem.createFile(at: path, finderInfo: finderInfo)
        }
        let fork = try Fork(path: path, kind: kind, permission: .readWrite)
        defer { try? fork.close() }
        // A fork that has resources already is dupFNErr.
        guard fork.size == 0 else { throw .duplicateFileName }
        try fork.replaceContents(with: ResourceMap.emptyFork)
    }

    /// CloseResFile: writes the file's changes and closes its fork.
    /// resFNotFound if no file of the number is open.
    public func close(_ reference: Int16) throws(MacError) {
        guard let index = files.firstIndex(where: { $0.reference == reference }) else { throw .resourceFileNotFound }
        let open = files.remove(at: index)
        if current == reference { current = files.first?.reference ?? 0 }
        defer { if open.file.fork != nil { try? fileSystem.close(reference) } }
        try open.file.update()
    }

    /// UseResFile: resFNotFound if no file of the number is open; 0 is the
    /// system's, here the first opened.
    public func use(_ reference: Int16) throws(MacError) {
        if reference == 0 {
            current = files.last?.reference ?? 0
            return
        }
        guard files.contains(where: { $0.reference == reference }) else { throw .resourceFileNotFound }
        current = reference
    }

    public func file(_ reference: Int16) -> ResourceFile? {
        files.first { $0.reference == reference }?.file
    }

    /// The files a search goes through: from the current one back, or the
    /// current one alone.
    public func searched(oneFile: Bool) -> ArraySlice<OpenFile> {
        guard let start = files.firstIndex(where: { $0.reference == current }) else { return [] }
        return oneFile ? files[start ... start] : files[start...]
    }

    // MARK: Finding resources

    /// A resource found, and the file it is in.
    public struct Found {
        public var reference: Int16
        public var resource: Resource
        /// Nil when the chain doesn't load resources (SetResLoad(false)).
        public var bytes: [UInt8]?
    }

    /// GetResource and Get1Resource: resNotFound if no file searched has it.
    public func get(type: FourCharCode, id: Int16, oneFile: Bool = false) throws(MacError) -> Found {
        for open in searched(oneFile: oneFile) {
            if let resource = open.file.resource(type: type, id: id) {
                return Found(reference: open.reference, resource: resource, bytes: loadsResources ? try open.file.bytes(type: type, id: id) : nil)
            }
        }
        throw .resourceNotFound
    }

    /// GetNamedResource and Get1NamedResource.
    public func get(type: FourCharCode, named name: PascalString, oneFile: Bool = false) throws(MacError) -> Found {
        for open in searched(oneFile: oneFile) {
            if let resource = open.file.resource(type: type, named: name) {
                let bytes = loadsResources ? try open.file.bytes(type: type, id: resource.id) : nil
                return Found(reference: open.reference, resource: resource, bytes: bytes)
            }
        }
        throw .resourceNotFound
    }

    /// GetIndResource and Get1IndResource: the index-th (from 1) resource of
    /// a type, counting through the files searched in order.
    public func get(type: FourCharCode, index: Int, oneFile: Bool = false) throws(MacError) -> Found {
        guard index >= 1 else { throw .resourceNotFound }
        var remaining = index
        for open in searched(oneFile: oneFile) {
            let resources = open.file.resources(ofType: type)
            if remaining <= resources.count {
                let resource = resources[remaining - 1]
                let bytes = loadsResources ? try open.file.bytes(type: type, id: resource.id) : nil
                return Found(reference: open.reference, resource: resource, bytes: bytes)
            }
            remaining -= resources.count
        }
        throw .resourceNotFound
    }

    /// CountResources and Count1Resources.
    public func count(type: FourCharCode, oneFile: Bool = false) -> Int {
        searched(oneFile: oneFile).reduce(0) { $0 + $1.file.resources(ofType: type).count }
    }

    /// CountTypes and Count1Types, GetIndType and Get1IndType: each type
    /// once, in the order the files searched have them.
    public func types(oneFile: Bool = false) -> [FourCharCode] {
        var seen: Set<FourCharCode> = []
        return searched(oneFile: oneFile).flatMap(\.file.types).filter { seen.insert($0).inserted }
    }

    /// UniqueID and Unique1ID: one no file searched has for the type.
    public func uniqueID(type: FourCharCode, oneFile: Bool = false) -> Int16 {
        let taken = Set(searched(oneFile: oneFile).flatMap { $0.file.resources(ofType: type).map(\.id) })
        var id: Int16 = 128
        while taken.contains(id), id < Int16.max { id += 1 }
        return id
    }

    /// UpdateResFile.
    public func update(_ reference: Int16) throws(MacError) {
        guard let file = file(reference) else { throw .resourceFileNotFound }
        try file.update()
    }
}
