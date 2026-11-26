// Icons: the classic icon resources a program keeps by ID ('ICON', 'ICN#',
// 'ics#', 'icl8', 'ics8', 'icl4', 'ics4'), color icons ('cicn'), and Mac OS
// X's icon families ('icns'), each made an ARGB image with its mask as
// alpha. Indexed icons use the system's 4- and 8-bit tables.

import GraphiteBase

/// An icon family's members by their types, and the best image of each
/// size they make.
public struct IconFamily: Sendable {

    /// The members' bytes, by type: 'ICN#', 'icl8', 'il32', 'l8mk'…
    public var members: [FourCharCode: [UInt8]]

    public init(members: [FourCharCode: [UInt8]] = [:]) {
        self.members = members
    }

    /// An 'icns' file or resource: its members after its header.
    public init(icns bytes: [UInt8]) throws(MacError) {
        var reader = BigEndianReader(bytes)
        do {
            guard try reader.read(UInt32.self) == FourCharCode("icns").rawValue else { throw MacError.parameter }
            let length = min(Int(try reader.read(UInt32.self)), bytes.count)
            members = [:]
            while reader.offset + 8 <= length {
                let type = FourCharCode(try reader.read(UInt32.self))
                let size = Int(try reader.read(UInt32.self))
                guard size >= 8 else { throw MacError.parameter }
                members[type] = Array(try reader.readBytes(size - 8))
            }
        } catch let error as MacError {
            throw error
        } catch {
            throw .parameter
        }
    }

    /// The sizes the family has images of.
    public var sizes: [Int] {
        [16, 32, 48, 128].filter { image(size: $0) != nil }
    }

    /// The family's best image of a size (16, 32, 48 or 128): 32-bit color
    /// with an 8-bit mask, else 8-bit, 4-bit or 1-bit, masked by the 8-bit
    /// mask or the 1-bit one.
    public func image(size: Int) -> PixelBuffer? {
        guard let names = Self.names[size] else { return nil }
        let mask = members[names.mask8].flatMap { $0.count >= size * size ? Array($0.prefix(size * size)) : nil }
            ?? members[names.bitmap].flatMap { Self.bits($0, size: size, offset: size * size / 8) }.map { $0.map { $0 ? 0xFF : 0 } }
        let image = PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: Int16(size), right: Int16(size)), format: .argb32)
        let colors: [UInt32]
        if let rgb = members[names.rgb].flatMap({ Self.unpackRGB($0, size: size, isThumbnail: size == 128) }) {
            colors = rgb
        } else if let indexed = members[names.indexed8].flatMap({ Self.indexed($0, size: size, depth: 8) }) {
            colors = indexed
        } else if let indexed = members[names.indexed4].flatMap({ Self.indexed($0, size: size, depth: 4) }) {
            colors = indexed
        } else if let bits = (members[names.bitmap] ?? (size == 32 ? members["ICON"] : nil)).flatMap({ Self.bits($0, size: size, offset: 0) }) {
            // 'ICON', the oldest, has no mask: all of it shows.
            colors = bits.map { $0 ? 0x000000 : 0xFFFFFF }
        } else {
            return nil
        }
        for index in 0 ..< size * size {
            let alpha = UInt32(mask?[index] ?? 0xFF)
            image.setValue(alpha << 24 | colors[index] & 0xFFFFFF, column: index % size, row: index / size)
        }
        return image
    }

    /// The members' types for each size.
    private static let names: [Int: (bitmap: FourCharCode, indexed4: FourCharCode, indexed8: FourCharCode, rgb: FourCharCode, mask8: FourCharCode)] = [
        16: ("ics#", "ics4", "ics8", "is32", "s8mk"),
        32: ("ICN#", "icl4", "icl8", "il32", "l8mk"),
        48: ("ich#", "ich4", "ich8", "ih32", "h8mk"),
        128: ("it3#", "it34", "it38", "it32", "t8mk"),
    ]

    /// A 1-bit image's pixels, from `offset` (a '#' member's mask follows
    /// its image).
    private static func bits(_ bytes: [UInt8], size: Int, offset: Int) -> [Bool]? {
        let count = size * size
        guard bytes.count >= offset + count / 8 else { return nil }
        return (0 ..< count).map { bytes[offset + $0 / 8] & (0x80 >> UInt8($0 % 8)) != 0 }
    }

    /// An indexed image's pixels' colors, through the system's table.
    private static func indexed(_ bytes: [UInt8], size: Int, depth: Int) -> [UInt32]? {
        guard bytes.count >= size * size * depth / 8, let table = ColorTable.standard(depth: depth) else { return nil }
        return (0 ..< size * size).map { index in
            let value = depth == 8 ? Int(bytes[index]) : Int(bytes[index / 2] >> (index % 2 == 0 ? 4 : 0) & 0xF)
            let color = table[value]
            return UInt32(color.red8) << 16 | UInt32(color.green8) << 8 | UInt32(color.blue8)
        }
    }

    /// A 32-bit member's pixels: three planes, red, green and blue, each
    /// run-length encoded (a byte n under 0x80 is n + 1 bytes as they are;
    /// over, the next byte n - 125 times), or 4 bytes a pixel unencoded when
    /// the member is that long. 'it32' starts with four zero bytes.
    private static func unpackRGB(_ bytes: [UInt8], size: Int, isThumbnail: Bool) -> [UInt32]? {
        let count = size * size
        if bytes.count == count * 4 {
            return (0 ..< count).map { UInt32(bytes[$0 * 4 + 1]) << 16 | UInt32(bytes[$0 * 4 + 2]) << 8 | UInt32(bytes[$0 * 4 + 3]) }
        }
        var index = isThumbnail ? 4 : 0
        var planes: [[UInt8]] = []
        for _ in 0 ..< 3 {
            var plane: [UInt8] = []
            plane.reserveCapacity(count)
            while plane.count < count {
                guard index < bytes.count else { return nil }
                let flag = Int(bytes[index])
                index += 1
                if flag < 0x80 {
                    guard index + flag + 1 <= bytes.count else { return nil }
                    plane += bytes[index ..< index + flag + 1]
                    index += flag + 1
                } else {
                    guard index < bytes.count else { return nil }
                    plane += [UInt8](repeating: bytes[index], count: flag - 125)
                    index += 1
                }
            }
            planes.append(Array(plane.prefix(count)))
        }
        return (0 ..< count).map { UInt32(planes[0][$0]) << 16 | UInt32(planes[1][$0]) << 8 | UInt32(planes[2][$0]) }
    }
}

/// A 'cicn' resource: a color icon of any size, its pixels with their own
/// color table, its mask, and a 1-bit image for 1-bit screens.
public struct ColorIcon: Sendable {

    public var bounds: Rect

    /// ARGB, the mask as alpha.
    public var image: [UInt32]

    /// The 'cicn' resource's IconPMap (50 bytes), maskBMap and iconBMap
    /// (14 each), iconData (4), then the mask's rows, the 1-bit image's,
    /// the pixel map's color table and its rows.
    public init(cicn bytes: [UInt8]) throws(MacError) {
        do {
            var reader = BigEndianReader(bytes)
            try reader.skip(4)                                          // baseAddr
            let rowBytes = Int(try reader.read(UInt16.self) & 0x3FFF)
            let bounds = try Self.rect(&reader)
            try reader.skip(2 + 2 + 4 + 4 + 4 + 2)                      // pmVersion … pixelType
            let depth = Int(try reader.read(UInt16.self))
            try reader.skip(2 + 2 + 4 + 4 + 4)                          // cmpCount … pmReserved
            try reader.skip(4)                                          // maskBMap's baseAddr
            let maskRowBytes = Int(try reader.read(UInt16.self))
            try reader.skip(8)
            try reader.skip(4)                                          // iconBMap's baseAddr
            let bitmapRowBytes = Int(try reader.read(UInt16.self))
            try reader.skip(8 + 4)                                      // its bounds, iconData
            let height = bounds.height, width = bounds.width
            guard width > 0, height > 0, width <= 1024, height <= 1024, [1, 2, 4, 8].contains(depth) else { throw MacError.parameter }
            let mask = Array(try reader.readBytes(maskRowBytes * height))
            try reader.skip(bitmapRowBytes * height)
            let tableStart = reader.offset
            try reader.skip(6)
            let entries = Int(try reader.read(UInt16.self)) + 1
            let table = try ColorTable(clut: Array(try BigEndianReader(bytes).subreader(at: tableStart, count: 8 + entries * 8).bytes))
            try reader.seek(to: tableStart + 8 + entries * 8)
            let pixels = Array(try reader.readBytes(rowBytes * height))
            self.bounds = bounds
            var image: [UInt32] = []
            image.reserveCapacity(width * height)
            for row in 0 ..< height {
                for column in 0 ..< width {
                    let bit = column * depth
                    let byte = pixels[row * rowBytes + bit / 8]
                    let value = Int(byte >> UInt8(8 - depth - bit % 8)) & (1 << depth - 1)
                    let color = table[value]
                    let masked = mask[row * maskRowBytes + column / 8] & (0x80 >> UInt8(column % 8)) != 0
                    image.append((masked ? 0xFF00_0000 : 0) | UInt32(color.red8) << 16 | UInt32(color.green8) << 8 | UInt32(color.blue8))
                }
            }
            self.image = image
        } catch let error as MacError {
            throw error
        } catch {
            throw .parameter
        }
    }

    /// The icon as an ARGB buffer.
    public var pixels: PixelBuffer {
        let buffer = PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: Int16(bounds.height), right: Int16(bounds.width)), format: .argb32)
        for (index, value) in image.enumerated() { buffer.setValue(value, column: index % bounds.width, row: index / bounds.width) }
        return buffer
    }

    private static func rect(_ reader: inout BigEndianReader) throws -> Rect {
        let top = Int16(bitPattern: try reader.read(UInt16.self)), left = Int16(bitPattern: try reader.read(UInt16.self))
        let bottom = Int16(bitPattern: try reader.read(UInt16.self)), right = Int16(bitPattern: try reader.read(UInt16.self))
        return Rect(top: top, left: left, bottom: bottom, right: right)
    }
}
