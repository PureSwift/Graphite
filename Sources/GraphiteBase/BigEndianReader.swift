// Reading the big-endian structures of resource forks, pictures, sounds and
// AppleDouble files from bytes. Every read checks its bounds and throws
// past the end; none traps, whatever the bytes say.

/// A read that went past the bytes there are.
public struct BigEndianReadError: Error, Hashable, Sendable {

    /// Where the read started.
    public var offset: Int

    /// How many bytes it wanted.
    public var count: Int

    /// How many bytes there were.
    public var available: Int

    public init(offset: Int, count: Int, available: Int) {
        self.offset = offset
        self.count = count
        self.available = available
    }
}

/// Reads typed fields one after another from bytes.
public struct BigEndianReader: Sendable {

    public let bytes: [UInt8]

    /// Where the next read starts.
    public var offset: Int

    public init(_ bytes: [UInt8], offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    public var count: Int { bytes.count }

    public var remaining: Int { max(0, bytes.count - offset) }

    public var isAtEnd: Bool { offset >= bytes.count }

    /// The range of `count` bytes at `offset`, if they're all there.
    private func range(at offset: Int, count: Int) throws(BigEndianReadError) -> Range<Int> {
        guard offset >= 0, count >= 0, offset <= bytes.count, count <= bytes.count - offset else {
            throw BigEndianReadError(offset: offset, count: count, available: bytes.count)
        }
        return offset ..< offset + count
    }

    /// An integer at `offset`, without moving.
    public func peek<T: FixedWidthInteger>(_ type: T.Type = T.self, at offset: Int) throws(BigEndianReadError) -> T {
        let range = try range(at: offset, count: MemoryLayout<T>.size)
        var value: T = 0
        for index in range {
            value = value << 8 | T(truncatingIfNeeded: bytes[index])
        }
        return value
    }

    public mutating func read<T: FixedWidthInteger>(_ type: T.Type = T.self) throws(BigEndianReadError) -> T {
        let value = try peek(T.self, at: offset)
        offset += MemoryLayout<T>.size
        return value
    }

    public mutating func readBytes(_ count: Int) throws(BigEndianReadError) -> ArraySlice<UInt8> {
        let range = try range(at: offset, count: count)
        offset = range.upperBound
        return bytes[range]
    }

    public mutating func skip(_ count: Int) throws(BigEndianReadError) {
        offset = try range(at: offset, count: count).upperBound
    }

    /// Moves to an offset from the start, which may be the end.
    public mutating func seek(to offset: Int) throws(BigEndianReadError) {
        _ = try range(at: offset, count: 0)
        self.offset = offset
    }

    /// Skips to the next multiple of `alignment` from the start; at the
    /// end, it stays there.
    public mutating func align(to alignment: Int) {
        guard alignment > 1 else { return }
        let padding = (alignment - offset % alignment) % alignment
        offset = min(offset + padding, max(offset, bytes.count))
    }

    /// A reader of the next `count` bytes, which this one moves past.
    public mutating func subreader(_ count: Int) throws(BigEndianReadError) -> BigEndianReader {
        BigEndianReader(Array(try readBytes(count)))
    }

    /// A reader of `count` bytes at `offset`, without moving.
    public func subreader(at offset: Int, count: Int) throws(BigEndianReadError) -> BigEndianReader {
        BigEndianReader(Array(bytes[try range(at: offset, count: count)]))
    }
}

// MARK: - Toolbox types

public extension BigEndianReader {

    mutating func readBool() throws(BigEndianReadError) -> Bool {
        try read(UInt8.self) != 0
    }

    mutating func readFourCharCode() throws(BigEndianReadError) -> FourCharCode {
        FourCharCode(rawValue: try read(UInt32.self))
    }

    /// A length byte and that many bytes.
    mutating func readPascalString() throws(BigEndianReadError) -> PascalString {
        let length = try read(UInt8.self)
        return PascalString(bytes: try readBytes(Int(length)))
    }

    /// A Pascal string in a field of `capacity` bytes and its length byte,
    /// as Str31 and Str63 fields in records are.
    mutating func readPascalString(capacity: Int) throws(BigEndianReadError) -> PascalString {
        let field = try readBytes(capacity + 1)
        return PascalString(lengthPrefixed: field)
    }

    /// Vertical, then horizontal.
    mutating func readPoint() throws(BigEndianReadError) -> Point {
        let v = try read(Int16.self)
        let h = try read(Int16.self)
        return Point(v: v, h: h)
    }

    /// Top, left, bottom, right.
    mutating func readRect() throws(BigEndianReadError) -> Rect {
        let top = try read(Int16.self)
        let left = try read(Int16.self)
        let bottom = try read(Int16.self)
        let right = try read(Int16.self)
        return Rect(top: top, left: left, bottom: bottom, right: right)
    }

    mutating func readFixed() throws(BigEndianReadError) -> Fixed {
        Fixed(rawValue: try read(Int32.self))
    }

    mutating func readExtended80() throws(BigEndianReadError) -> Extended80 {
        let signAndExponent = try read(UInt16.self)
        let mantissa = try read(UInt64.self)
        return Extended80(signAndExponent: signAndExponent, mantissa: mantissa)
    }
}
