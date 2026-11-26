// Pixels as QuickDraw keeps them, on every CPU: 1, 2, 4 and 8 bits indexed
// through a color table, the leftmost pixel in a byte's high bits; 16-bit
// xRGB 1-5-5-5 and 32-bit ARGB, both big-endian. A buffer's memory is its
// own, or memory it is given: a program's, which the program reads and
// writes too (NewGWorldFromPtr, a PixMap's baseAddr in a guest's memory).

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import GraphiteBase

/// How a buffer's pixels are kept.
public enum PixelFormat: Hashable, Sendable {

    /// 1, 2, 4 or 8 bits, a color table's index.
    case indexed(depth: Int)

    /// xRGB 1-5-5-5, big-endian.
    case rgb555

    /// ARGB, 8 bits a component, big-endian.
    case argb32

    /// The format QuickDraw gives a depth: nil for one it hasn't.
    public init?(depth: Int) {
        switch depth {
        case 1, 2, 4, 8: self = .indexed(depth: depth)
        case 16: self = .rgb555
        case 32: self = .argb32
        default: return nil
        }
    }

    /// Bits a pixel.
    public var depth: Int {
        switch self {
        case .indexed(let depth): depth
        case .rgb555: 16
        case .argb32: 32
        }
    }

    public var isIndexed: Bool {
        if case .indexed = self { return true }
        return false
    }

    /// The fewest bytes a row of `width` pixels takes, rounded up to four
    /// as GWorlds' rows are.
    public func minimumRowBytes(width: Int) -> Int {
        (max(0, width) * depth + 31) / 32 * 4
    }
}

/// A rectangle of pixels.
public final class PixelBuffer {

    public let format: PixelFormat

    /// Where the first row starts.
    public private(set) var baseAddress: UnsafeMutableRawPointer

    /// How far apart rows start.
    public private(set) var rowBytes: Int

    /// The coordinates the pixels cover: the first row's first pixel is
    /// `bounds.topLeft`. SetOrigin moves them; the pixels stay.
    public var bounds: Rect

    /// An indexed buffer's colors.
    public var colorTable: ColorTable

    /// The entries of the color table that colors are not matched to,
    /// because a program keeps them for its own use (ReserveEntry).
    public var reservedEntries: Set<Int> = []

    /// Whether the memory is the buffer's to free.
    private let ownsMemory: Bool

    /// New pixels, cleared to zero: white for indexed ones, black for direct
    /// ones, as a new GWorld's are before it is erased.
    public init(bounds: Rect, format: PixelFormat, colorTable: ColorTable? = nil, rowBytes: Int? = nil) {
        self.format = format
        self.bounds = bounds
        self.rowBytes = max(rowBytes ?? 0, format.minimumRowBytes(width: bounds.width))
        let size = max(1, self.rowBytes * max(0, bounds.height))
        baseAddress = calloc(1, size)!
        ownsMemory = true
        self.colorTable = colorTable ?? ColorTable.standard(depth: format.depth) ?? ColorTable(colors: [])
    }

    /// Pixels in memory that isn't the buffer's, which must hold
    /// `bounds.height` rows of `rowBytes` for as long as the buffer is used.
    public init(wrapping memory: UnsafeMutableRawPointer, rowBytes: Int, bounds: Rect, format: PixelFormat, colorTable: ColorTable? = nil) {
        self.format = format
        self.bounds = bounds
        self.rowBytes = rowBytes
        baseAddress = memory
        ownsMemory = false
        self.colorTable = colorTable ?? ColorTable.standard(depth: format.depth) ?? ColorTable(colors: [])
    }

    deinit {
        if ownsMemory { free(baseAddress) }
    }

    /// The bytes the pixels take.
    public var byteCount: Int { rowBytes * max(0, bounds.height) }

    public var width: Int { bounds.width }
    public var height: Int { bounds.height }

    // MARK: Pixel values

    /// A pixel's value as stored: an index, or 16 or 32 bits of color; nil
    /// outside the buffer.
    public func value(at point: Point) -> UInt32? {
        guard bounds.contains(point) else { return nil }
        return value(column: Int(point.h) - Int(bounds.left), row: Int(point.v) - Int(bounds.top))
    }

    public func setValue(_ value: UInt32, at point: Point) {
        guard bounds.contains(point) else { return }
        setValue(value, column: Int(point.h) - Int(bounds.left), row: Int(point.v) - Int(bounds.top))
    }

    /// A pixel's value by its column and row from the buffer's first.
    public func value(column: Int, row: Int) -> UInt32 {
        let line = baseAddress + row * rowBytes
        switch format {
        case .indexed(let depth):
            let bit = column * depth
            let byte = line.load(fromByteOffset: bit / 8, as: UInt8.self)
            let shift = 8 - depth - bit % 8
            return UInt32(byte >> UInt8(shift)) & (1 << UInt32(depth) - 1)
        case .rgb555:
            return UInt32(UInt16(bigEndian: line.loadUnaligned(fromByteOffset: column * 2, as: UInt16.self)))
        case .argb32:
            return UInt32(bigEndian: line.loadUnaligned(fromByteOffset: column * 4, as: UInt32.self))
        }
    }

    public func setValue(_ value: UInt32, column: Int, row: Int) {
        let line = baseAddress + row * rowBytes
        switch format {
        case .indexed(let depth):
            let bit = column * depth
            let shift = 8 - depth - bit % 8
            let mask = UInt8(truncatingIfNeeded: (1 << depth - 1) << shift)
            let byte = line.load(fromByteOffset: bit / 8, as: UInt8.self)
            let bits = UInt8(truncatingIfNeeded: value << UInt32(shift)) & mask
            line.storeBytes(of: byte & ~mask | bits, toByteOffset: bit / 8, as: UInt8.self)
        case .rgb555:
            line.storeBytes(of: UInt16(truncatingIfNeeded: value).bigEndian, toByteOffset: column * 2, as: UInt16.self)
        case .argb32:
            line.storeBytes(of: value.bigEndian, toByteOffset: column * 4, as: UInt32.self)
        }
    }

    // MARK: Colors

    /// A color as this buffer stores it: the nearest index in its table, or
    /// its bits; 32-bit pixels opaque.
    public func value(for color: RGBColor) -> UInt32 {
        switch format {
        case .indexed: UInt32(colorTable.index(of: color, excluding: reservedEntries))
        case .rgb555: UInt32(color.red >> 11) << 10 | UInt32(color.green >> 11) << 5 | UInt32(color.blue >> 11)
        case .argb32: 0xFF00_0000 | UInt32(color.red8) << 16 | UInt32(color.green8) << 8 | UInt32(color.blue8)
        }
    }

    /// The color a stored value is.
    public func color(for value: UInt32) -> RGBColor {
        switch format {
        case .indexed:
            return colorTable[Int(value)]
        case .rgb555:
            // Five bits widened to sixteen, repeating, as QuickDraw does.
            func widen(_ bits: UInt32) -> UInt16 {
                let five = UInt16(bits & 0x1F)
                return five << 11 | five << 6 | five << 1 | five >> 4
            }
            return RGBColor(red: widen(value >> 10), green: widen(value >> 5), blue: widen(value))
        case .argb32:
            return RGBColor(red8: UInt8(value >> 16 & 0xFF), green8: UInt8(value >> 8 & 0xFF), blue8: UInt8(value & 0xFF))
        }
    }

    /// GetCPixel: the color at a point; nil outside the buffer.
    public func color(at point: Point) -> RGBColor? {
        value(at: point).map(color(for:))
    }

    /// SetCPixel.
    public func setColor(_ color: RGBColor, at point: Point) {
        setValue(value(for: color), at: point)
    }

    /// Sets every pixel of a rectangle, clipped to the buffer, to a value.
    public func fill(_ rect: Rect, with value: UInt32) {
        let area = rect.intersection(bounds)
        guard !area.isEmpty else { return }
        let firstColumn = Int(area.left) - Int(bounds.left)
        for row in (Int(area.top) - Int(bounds.top)) ..< (Int(area.bottom) - Int(bounds.top)) {
            for column in firstColumn ..< firstColumn + area.width {
                setValue(value, column: column, row: row)
            }
        }
    }

    /// The pixels' bytes, row after row, `rowBytes` apart.
    public var bytes: [UInt8] {
        Array(UnsafeRawBufferPointer(start: baseAddress, count: byteCount))
    }

    /// Moves the buffer to other memory, as UpdateGWorld and a host that
    /// reallocates a program's pixels do: the pixels aren't copied.
    public func rebase(to memory: UnsafeMutableRawPointer, rowBytes: Int) {
        precondition(!ownsMemory, "a buffer that owns its memory isn't moved")
        baseAddress = memory
        self.rowBytes = rowBytes
    }
}
