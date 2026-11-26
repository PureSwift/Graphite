// PackBits (Inside Macintosh: Imaging With QuickDraw, A-81), the run-length
// encoding of pictures' and icons' rows: a flag byte n, then n + 1 bytes as
// they are for n from 0 to 127, or one unit repeated 1 - n times for n from
// -1 to -127; -128 is skipped. Pictures' 16-bit pixels repeat two bytes at a
// time.

import protocol Foundation.ContiguousBytes
import GraphiteBase

public enum PackBits {

    /// Unpacks `count` bytes from a reader, each repeated unit `unit` bytes
    /// (1, or 2 for 16-bit pixels). Throws if the data ends first.
    public static func unpack(_ reader: inout BigEndianReader, count: Int, unit: Int = 1) throws(BigEndianReadError) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)
        while bytes.count < count {
            let flag = Int8(bitPattern: try reader.read(UInt8.self))
            if flag >= 0 {
                bytes += try reader.readBytes((Int(flag) + 1) * unit)
            } else if flag != -128 {
                let run = try reader.readBytes(unit)
                for _ in 0 ..< 1 - Int(flag) { bytes += run }
            }
        }
        return Array(bytes.prefix(count))
    }

    /// Unpacks all of `data`.
    public static func unpack(_ data: some ContiguousBytes, count: Int, unit: Int = 1) throws(MacError) -> [UInt8] {
        var reader = BigEndianReader(data)
        do {
            return try unpack(&reader, count: count, unit: unit)
        } catch {
            throw .parameter
        }
    }

    /// Packs bytes as PackBits does: runs of three or more the same as a
    /// repeat, the rest as literals of at most 128.
    public static func pack(_ input: some ContiguousBytes) -> [UInt8] {
        let bytes = Array(copying: input)
        var packed: [UInt8] = []
        var index = 0
        var literal: [UInt8] = []
        func flushLiteral() {
            var start = 0
            while start < literal.count {
                let chunk = literal[start ..< min(start + 128, literal.count)]
                packed.append(UInt8(chunk.count - 1))
                packed += chunk
                start += 128
            }
            literal.removeAll()
        }
        while index < bytes.count {
            var run = 1
            while index + run < bytes.count, bytes[index + run] == bytes[index], run < 128 { run += 1 }
            if run >= 3 {
                flushLiteral()
                packed.append(UInt8(bitPattern: Int8(1 - run)))
                packed.append(bytes[index])
                index += run
            } else {
                literal.append(bytes[index])
                index += 1
            }
        }
        flushLiteral()
        return packed
    }
}
