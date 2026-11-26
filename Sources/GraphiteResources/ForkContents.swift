// A fork read whole, for the files programs keep in one piece.

import Foundation
import GraphiteBase
import GraphiteFiles

public extension Fork {

    /// The fork's bytes, from its start to its end; the mark moves to the
    /// end. A data fork opened for reading only is mapped into memory, not
    /// read, so it costs pages as they are used. The map is a view of the
    /// file, not a snapshot: truncating the file while it is held can crash
    /// the process that reads past the new end. Any other fork is read into
    /// memory. memFullErr for one past 2 GB.
    func contents() throws(MacError) -> Data {
        let count = size
        guard count <= Int64(Int32.max) else { throw .memoryFull }
        if kind == .data, !canWrite, count > 0,
           let mapped = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped),
           mapped.count == Int(count) {
            return mapped
        }
        var data = Data(count: Int(count))
        var result = Result<Int, MacError>.success(0)
        data.withUnsafeMutableBytes { buffer in
            result = Result { () throws(MacError) -> Int in try read(into: buffer, from: .start(0)) }
        }
        data.removeLast(Int(count) - (try result.get()))
        return data
    }
}
