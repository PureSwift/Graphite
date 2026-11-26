// The pixels a picture copies (Inside Macintosh: Imaging With QuickDraw,
// A-22): a bitmap or a pixel map's record, its color table if it is
// indexed, and its rows, as they are when rowBytes is under 8 and packed
// with PackBits otherwise, each row after its packed length (a byte, or a
// word when rowBytes is over 250). 32-bit pixels are packed as planes of
// components, alpha first when there are four; 16-bit ones two bytes at a
// time.

import GraphiteBase

enum PicturePixels {

    /// A bitmap's or pixel map's record, which the pixels follow later.
    struct Header {
        var rowBytes: Int
        var bounds: Rect
        var depth: Int
        var packType: Int16
        var componentCount: Int16
        var colorTable: ColorTable?
    }

    /// A bitmap's or pixel map's record and color table, after the opcode
    /// and, for DirectBits, its baseAddr. `isDirect` says there's no color
    /// table.
    static func readHeader(_ reader: inout BigEndianReader, isDirect: Bool) throws -> Header {
        let rawRowBytes = try reader.read(UInt16.self)
        let isPixelMap = rawRowBytes & 0x8000 != 0
        let rowBytes = Int(rawRowBytes & 0x3FFF)
        let bounds = try readRect(&reader)
        var depth = 1
        var packType: Int16 = 0
        var componentCount: Int16 = 1
        var colorTable: ColorTable?
        if isPixelMap {
            try reader.skip(2)                                   // pmVersion
            packType = Int16(bitPattern: try reader.read(UInt16.self))
            try reader.skip(4 + 4 + 4 + 2)                       // packSize, hRes, vRes, pixelType
            depth = Int(try reader.read(UInt16.self))
            componentCount = Int16(bitPattern: try reader.read(UInt16.self))
            try reader.skip(2 + 4 + 4 + 4)                       // cmpSize, planeBytes, pmTable, pmReserved
            if !isDirect { colorTable = try readColorTable(&reader) }
        }
        return Header(rowBytes: rowBytes, bounds: bounds, depth: depth, packType: packType, componentCount: componentCount, colorTable: colorTable)
    }

    /// The pixels a header's record says, after the rectangles, mode and
    /// mask region that come between them in a picture.
    static func readPixels(_ reader: inout BigEndianReader, _ header: Header) throws -> PixelBuffer {
        let rowBytes = header.rowBytes, bounds = header.bounds, depth = header.depth
        let packType = header.packType, componentCount = header.componentCount, colorTable = header.colorTable
        let height = max(0, bounds.height), width = max(0, bounds.width)
        guard height <= 0x4000, width <= 0x4000, rowBytes <= 0x4000 else { throw MacError.parameter }
        switch depth {
        case 1, 2, 4, 8:
            let buffer = PixelBuffer(bounds: bounds, format: .indexed(depth: depth), colorTable: colorTable, rowBytes: max(rowBytes, 1))
            for row in 0 ..< height {
                let bytes = try readRow(&reader, rowBytes: rowBytes, unit: 1)
                copy(bytes, into: buffer, row: row)
            }
            return buffer
        case 16:
            let buffer = PixelBuffer(bounds: bounds, format: .rgb555, rowBytes: max(rowBytes, width * 2))
            for row in 0 ..< height {
                let bytes = try readRow(&reader, rowBytes: rowBytes, unit: packType == 3 || packType == 0 ? 2 : 1)
                copy(bytes, into: buffer, row: row)
            }
            return buffer
        case 32:
            let buffer = PixelBuffer(bounds: bounds, format: .argb32)
            for row in 0 ..< height {
                if rowBytes < 8 || packType == 1 {
                    // Unpacked ARGB.
                    copy(Array(try reader.readBytes(rowBytes)), into: buffer, row: row)
                } else if packType == 2 {
                    // Unpacked RGB, no alpha.
                    let bytes = Array(try reader.readBytes(width * 3))
                    for column in 0 ..< width {
                        let value = 0xFF00_0000 | UInt32(bytes[column * 3]) << 16 | UInt32(bytes[column * 3 + 1]) << 8 | UInt32(bytes[column * 3 + 2])
                        buffer.setValue(value, column: column, row: row)
                    }
                } else {
                    // Planes: alpha first when there are four.
                    let planes = Int(componentCount == 4 ? 4 : 3)
                    let bytes = try readRow(&reader, rowBytes: rowBytes, unit: 1, count: width * planes)
                    for column in 0 ..< width {
                        let alpha: UInt32 = planes == 4 ? UInt32(bytes[column]) : 0xFF
                        let base = planes == 4 ? width : 0
                        let red = UInt32(bytes[base + column]), green = UInt32(bytes[base + width + column]), blue = UInt32(bytes[base + 2 * width + column])
                        buffer.setValue(alpha << 24 | red << 16 | green << 8 | blue, column: column, row: row)
                    }
                }
            }
            return buffer
        default:
            throw MacError.parameter
        }
    }

    /// A row's bytes: as they are under 8 bytes, else packed after their
    /// packed length.
    private static func readRow(_ reader: inout BigEndianReader, rowBytes: Int, unit: Int, count: Int? = nil) throws -> [UInt8] {
        let wanted = count ?? rowBytes
        guard rowBytes >= 8 else { return Array(try reader.readBytes(wanted)) }
        let packedLength = rowBytes > 250 ? Int(try reader.read(UInt16.self)) : Int(try reader.read(UInt8.self))
        var packed = try reader.subreader(packedLength)
        return (try? PackBits.unpack(&packed, count: wanted, unit: unit)) ?? Array(repeating: 0, count: wanted)
    }

    private static func copy(_ bytes: [UInt8], into buffer: PixelBuffer, row: Int) {
        let count = min(bytes.count, buffer.rowBytes)
        guard count > 0 else { return }
        bytes.withUnsafeBytes { (buffer.baseAddress + row * buffer.rowBytes).copyMemory(from: $0.baseAddress!, byteCount: count) }
    }

    static func readRect(_ reader: inout BigEndianReader) throws -> Rect {
        let top = Int16(bitPattern: try reader.read(UInt16.self)), left = Int16(bitPattern: try reader.read(UInt16.self))
        let bottom = Int16(bitPattern: try reader.read(UInt16.self)), right = Int16(bitPattern: try reader.read(UInt16.self))
        return Rect(top: top, left: left, bottom: bottom, right: right)
    }

    /// A color table as pictures and 'clut's keep it.
    static func readColorTable(_ reader: inout BigEndianReader) throws -> ColorTable {
        let start = reader.offset
        try reader.skip(6)
        let count = Int(try reader.read(UInt16.self)) + 1
        let table = try ColorTable(clut: Array(reader.bytes[start ..< min(reader.bytes.count, start + 8 + count * 8)]))
        try reader.seek(to: start + 8 + count * 8)
        return table
    }
}
