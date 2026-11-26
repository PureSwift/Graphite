// Bytes from anywhere: an array, a Data (which may be a file mapped into
// memory), a raw buffer or a slice of one. Parsers take `some
// ContiguousBytes` so a caller keeps what it has, and copy out only what
// they keep.

import protocol Foundation.ContiguousBytes

public extension Array where Element == UInt8 {

    /// The bytes of anything contiguous, copied. An array is returned as it
    /// is, and shares its storage until one of them changes. Copying a
    /// mapped Data reads all of it.
    init(copying bytes: some ContiguousBytes) {
        if let array = bytes as? [UInt8] {
            self = array
        } else {
            self = bytes.withUnsafeBytes { Array($0) }
        }
    }
}

public extension BigEndianReader {

    /// A reader of the bytes of anything contiguous, from `offset`.
    init(_ bytes: some ContiguousBytes, offset: Int = 0) {
        self.init(Array(copying: bytes), offset: offset)
    }
}
