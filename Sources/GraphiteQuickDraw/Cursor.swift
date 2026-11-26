// Cursors: a 16×16 image of 1-bit data and mask with a hot spot ('CURS',
// SetCursor's Cursor), and color cursors ('crsr') with a pixel map as well.
// Where data and mask are both set the pixel is black; mask alone, white;
// data alone, the screen inverted; neither, the screen as it is.

import protocol Foundation.ContiguousBytes
import struct Foundation.Data
import GraphiteBase

public struct Cursor: Hashable, Sendable {

    /// The 1-bit image's rows, the high bit leftmost.
    public var data: [UInt16]

    public var mask: [UInt16]

    /// The point of the cursor that is the mouse's location.
    public var hotSpot: Point

    /// A color cursor's pixels as ARGB, its mask as alpha, row after row;
    /// nil for a 1-bit one.
    public var colorImage: [UInt32]?

    /// The color image's width; its height is its count over this.
    public var colorWidth: Int

    public init(data: [UInt16], mask: [UInt16], hotSpot: Point, colorImage: [UInt32]? = nil, colorWidth: Int = 0) {
        self.data = Array((data + [UInt16](repeating: 0, count: 16)).prefix(16))
        self.mask = Array((mask + [UInt16](repeating: 0, count: 16)).prefix(16))
        self.hotSpot = hotSpot
        self.colorImage = colorImage
        self.colorWidth = colorImage == nil ? 0 : colorWidth
    }

    /// A 'CURS' resource or a Cursor record: data, mask, hot spot (68
    /// bytes).
    public init(curs bytes: some ContiguousBytes) throws(MacError) {
        do {
            var reader = BigEndianReader(bytes)
            let data = try (0 ..< 16).map { _ throws(BigEndianReadError) in try reader.read(UInt16.self) }
            let mask = try (0 ..< 16).map { _ throws(BigEndianReadError) in try reader.read(UInt16.self) }
            let v = Int16(bitPattern: try reader.read(UInt16.self)), h = Int16(bitPattern: try reader.read(UInt16.self))
            self.init(data: data, mask: mask, hotSpot: Point(v: v, h: h))
        } catch {
            throw .parameter
        }
    }

    /// The Cursor record's 68 bytes.
    public var curs: [UInt8] {
        var writer = BigEndianWriter()
        for row in data { writer.write(row) }
        for row in mask { writer.write(row) }
        writer.write(UInt16(bitPattern: hotSpot.v))
        writer.write(UInt16(bitPattern: hotSpot.h))
        return writer.bytes
    }

    /// A 'crsr' resource: its CCrsr record (crsrType, offsets of its pixel
    /// map and pixels, its 1-bit data, mask and hot spot), then the pixel
    /// map, which points to its color table by offset too.
    public init(crsr bytes: some ContiguousBytes) throws(MacError) {
        let source = Data(zeroBased: bytes)
        do {
            var reader = BigEndianReader(source)
            try reader.skip(2)                                          // crsrType
            let mapOffset = Int(try reader.read(UInt32.self))
            let dataOffset = Int(try reader.read(UInt32.self))
            try reader.skip(4 + 2 + 4)                                  // crsrXData, crsrXValid, crsrXHandle
            let data = try (0 ..< 16).map { _ throws(BigEndianReadError) in try reader.read(UInt16.self) }
            let mask = try (0 ..< 16).map { _ throws(BigEndianReadError) in try reader.read(UInt16.self) }
            let v = Int16(bitPattern: try reader.read(UInt16.self)), h = Int16(bitPattern: try reader.read(UInt16.self))
            var map = try BigEndianReader(source).subreader(at: mapOffset, count: 50)
            try map.skip(4)
            let rowBytes = Int(try map.read(UInt16.self) & 0x3FFF)
            let top = Int(Int16(bitPattern: try map.read(UInt16.self))), left = Int(Int16(bitPattern: try map.read(UInt16.self)))
            let bottom = Int(Int16(bitPattern: try map.read(UInt16.self))), right = Int(Int16(bitPattern: try map.read(UInt16.self)))
            try map.skip(2 + 2 + 4 + 4 + 4 + 2)
            let depth = Int(try map.read(UInt16.self))
            try map.skip(2 + 2 + 4)
            let tableOffset = Int(try map.read(UInt32.self))
            let width = right - left, height = bottom - top
            guard width > 0, height > 0, width <= 64, height <= 64, [1, 2, 4, 8].contains(depth) else { throw MacError.parameter }
            var tableReader = try BigEndianReader(source).subreader(at: tableOffset, count: 8)
            try tableReader.skip(6)
            let entries = Int(try tableReader.read(UInt16.self)) + 1
            let table = try ColorTable(clut: try BigEndianReader(source).subreader(at: tableOffset, count: 8 + entries * 8).bytes)
            let pixels = try BigEndianReader(source).subreader(at: dataOffset, count: rowBytes * height).bytes
            var image: [UInt32] = []
            for row in 0 ..< height {
                for column in 0 ..< width {
                    let bit = column * depth
                    let value = Int(pixels[row * rowBytes + bit / 8] >> UInt8(8 - depth - bit % 8)) & (1 << depth - 1)
                    let color = table[value]
                    let masked = row < 16 && column < 16 && mask[row] & (0x8000 >> UInt16(column)) != 0
                    image.append((masked ? 0xFF00_0000 : 0) | UInt32(color.red8) << 16 | UInt32(color.green8) << 8 | UInt32(color.blue8))
                }
            }
            self.init(data: data, mask: mask, hotSpot: Point(v: v, h: h), colorImage: image, colorWidth: width)
        } catch let error as MacError {
            throw error
        } catch {
            throw .parameter
        }
    }

    /// What a pixel of the 1-bit image does.
    public enum Pixel: Hashable, Sendable {
        case black, white, inverted, transparent
    }

    public func pixel(row: Int, column: Int) -> Pixel {
        let bit = UInt16(0x8000) >> UInt16(column)
        switch (data[row] & bit != 0, mask[row] & bit != 0) {
        case (true, true): return .black
        case (false, true): return .white
        case (true, false): return .inverted
        case (false, false): return .transparent
        }
    }

    /// The cursor as ARGB for a host's cursor, 16×16 or the color image's
    /// size: inverted pixels are black, as hosts that can't invert show them.
    public var argb: [UInt32] {
        if let colorImage { return colorImage }
        return (0 ..< 256).map { index in
            switch pixel(row: index / 16, column: index % 16) {
            case .black, .inverted: return 0xFF00_0000
            case .white: return 0xFFFF_FFFF
            case .transparent: return 0
            }
        }
    }

    /// The arrow, InitCursor's and QuickDraw's arrow global.
    public static let arrow = Cursor(
        data: [0x0000, 0x4000, 0x6000, 0x7000, 0x7800, 0x7C00, 0x7E00, 0x7F00,
               0x7F80, 0x7C00, 0x6C00, 0x4600, 0x0600, 0x0300, 0x0300, 0x0000],
        mask: [0xC000, 0xE000, 0xF000, 0xF800, 0xFC00, 0xFE00, 0xFF00, 0xFF80,
               0xFFC0, 0xFFE0, 0xFE00, 0xEF00, 0xCF00, 0x8780, 0x0780, 0x0380],
        hotSpot: Point(v: 1, h: 1)
    )
}
