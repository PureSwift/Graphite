// 'STR#' and 'STR ' resources (Inside Macintosh: Text, 5-46): a count and
// that many Pascal strings, and a single Pascal string. GetIndString reads
// the first.

import protocol Foundation.ContiguousBytes
import GraphiteBase

/// A 'STR#' resource.
public struct StringList: Hashable, Sendable {

    public static var resourceType: FourCharCode { "STR#" }

    public var strings: [PascalString]

    public init(strings: [PascalString]) {
        self.strings = strings
    }

    /// mapReadErr if the bytes end before the strings their count says.
    public init(bytes: some ContiguousBytes) throws(MacError) {
        var reader = BigEndianReader(bytes)
        do {
            let count = Int(try reader.read(UInt16.self))
            strings = []
            strings.reserveCapacity(count)
            for _ in 0 ..< count {
                let length = Int(try reader.read(UInt8.self))
                strings.append(PascalString(bytes: try reader.readBytes(length)))
            }
        } catch {
            throw .mapRead
        }
    }

    public var bytes: [UInt8] {
        var writer = BigEndianWriter()
        writer.write(UInt16(truncatingIfNeeded: strings.count))
        for string in strings { writer.write(bytes: string.lengthPrefixed) }
        return writer.bytes
    }

    /// GetIndString: the index-th string, from 1; an empty one past the end.
    public subscript(index: Int) -> PascalString {
        index >= 1 && index <= strings.count ? strings[index - 1] : PascalString()
    }
}

/// A 'STR ' resource.
public struct StringResource: Hashable, Sendable {

    public static var resourceType: FourCharCode { "STR " }

    public var string: PascalString

    public init(string: PascalString) {
        self.string = string
    }

    /// A length longer than the bytes takes what there is, as GetString's
    /// callers found.
    public init(bytes: some ContiguousBytes) {
        string = PascalString(lengthPrefixed: Array(copying: bytes))
    }

    public var bytes: [UInt8] { string.lengthPrefixed }
}
