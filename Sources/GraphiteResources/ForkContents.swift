// A fork read whole, for the files programs keep in one piece.

import GraphiteBase
import GraphiteFiles

public extension Fork {

    /// The fork's bytes, from its start to its end. memFullErr for one past
    /// 2 GB.
    func contents() throws(MacError) -> [UInt8] {
        let count = size
        guard count <= Int64(Int32.max) else { throw .memoryFull }
        return try readAll(count: Int(count))
    }
}
