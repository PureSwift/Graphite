// Writing big-endian structures, as resource forks and AppleDouble files
// are written back: fields appended in order, and offsets filled in once
// what they point at has been written.

/// Appends typed fields to bytes.
public struct BigEndianWriter: Sendable {

    public private(set) var bytes: [UInt8]

    public init(capacity: Int = 0) {
        self.bytes = []
        self.bytes.reserveCapacity(capacity)
    }

    public var count: Int { bytes.count }

    public mutating func write<T: FixedWidthInteger>(_ value: T) {
        let size = MemoryLayout<T>.size
        for index in 0 ..< size {
            bytes.append(UInt8(truncatingIfNeeded: value >> ((size - 1 - index) * 8)))
        }
    }

    public mutating func write(bytes: some Sequence<UInt8>) {
        self.bytes.append(contentsOf: bytes)
    }

    /// `count` zero bytes.
    public mutating func writeZeros(_ count: Int) {
        bytes.append(contentsOf: repeatElement(0, count: max(0, count)))
    }

    /// Zeros to the next multiple of `alignment`.
    public mutating func align(to alignment: Int) {
        guard alignment > 1 else { return }
        writeZeros((alignment - bytes.count % alignment) % alignment)
    }

    /// Writes over an integer already written at `offset`, as an offset or
    /// a length known only later. False if it isn't inside what's written.
    @discardableResult
    public mutating func set<T: FixedWidthInteger>(_ value: T, at offset: Int) -> Bool {
        let size = MemoryLayout<T>.size
        guard offset >= 0, offset <= bytes.count - size else { return false }
        for index in 0 ..< size {
            bytes[offset + index] = UInt8(truncatingIfNeeded: value >> ((size - 1 - index) * 8))
        }
        return true
    }
}

// MARK: - Toolbox types

public extension BigEndianWriter {

    mutating func write(_ value: Bool) {
        write(UInt8(value ? 1 : 0))
    }

    mutating func write(_ code: FourCharCode) {
        write(code.rawValue)
    }

    /// The length byte and the bytes.
    mutating func write(_ string: PascalString) {
        write(bytes: string.lengthPrefixed)
    }

    /// The string in a field of `capacity` bytes after its length byte,
    /// zeros after it; a longer string is cut to fit.
    mutating func write(_ string: PascalString, capacity: Int) {
        let kept = string.bytes.prefix(max(0, capacity))
        write(UInt8(kept.count))
        write(bytes: kept)
        writeZeros(capacity - kept.count)
    }

    mutating func write(_ point: Point) {
        write(point.v)
        write(point.h)
    }

    mutating func write(_ rect: Rect) {
        write(rect.top)
        write(rect.left)
        write(rect.bottom)
        write(rect.right)
    }

    mutating func write(_ value: Fixed) {
        write(value.rawValue)
    }

    mutating func write(_ value: Extended80) {
        write(value.signAndExponent)
        write(value.mantissa)
    }
}
