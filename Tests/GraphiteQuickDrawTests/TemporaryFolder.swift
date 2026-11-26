#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// A folder of its own for a test, deleted with what's in it at the end.
final class TemporaryFolder {

    let path: String

    init() {
        var template = Array("/tmp/graphite-XXXXXX".utf8CString)
        let made = template.withUnsafeMutableBufferPointer { mkdtemp($0.baseAddress!) }
        // The real path: /tmp is a link on macOS.
        let resolved = realpath(made!, nil)!
        path = String(cString: resolved)
        free(resolved)
    }

    deinit {
        remove(path)
    }

    private func remove(_ path: String) {
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        if info.st_mode & S_IFMT == S_IFDIR, let directory = opendir(path) {
            var names: [String] = []
            while let entry = readdir(directory) {
                let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                if name != "." && name != ".." { names.append(name) }
            }
            closedir(directory)
            for name in names { remove(path + "/" + name) }
            rmdir(path)
        } else {
            unlink(path)
        }
    }

    func path(_ name: String) -> String { path + "/" + name }

    func write(_ name: String, _ bytes: [UInt8]) {
        let descriptor = open(path(name), O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        precondition(descriptor >= 0)
        _ = bytes.withUnsafeBytes { systemWrite(descriptor, $0.baseAddress, $0.count) }
        close(descriptor)
    }

    func read(_ name: String) -> [UInt8]? {
        let descriptor = open(path(name), O_RDONLY)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var bytes: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = chunk.withUnsafeMutableBytes { systemRead(descriptor, $0.baseAddress, $0.count) }
            if count <= 0 { return bytes }
            bytes += chunk[0 ..< count]
        }
    }

    func makeFolder(_ name: String) {
        mkdir(path(name), 0o755)
    }

    func exists(_ name: String) -> Bool {
        var info = stat()
        return stat(path(name), &info) == 0
    }
}

private func systemWrite(_ descriptor: Int32, _ bytes: UnsafeRawPointer?, _ count: Int) -> Int { write(descriptor, bytes, count) }

private func systemRead(_ descriptor: Int32, _ bytes: UnsafeMutableRawPointer?, _ count: Int) -> Int { read(descriptor, bytes, count) }
