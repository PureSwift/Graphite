// Decoders of compressed sound: G.711 µ-law and A-law, and IMA ADPCM as
// Apple frames it ('ima4'). Written from the formats' descriptions.

/// Turns packets of compressed samples into 16-bit ones.
public protocol SoundCodec: Sendable {

    /// The bytes one channel's packet takes.
    var bytesPerPacket: Int { get }

    /// The samples one channel's packet holds.
    var samplesPerPacket: Int { get }

    /// The samples of the packets, interleaved over the channels as the
    /// packets are: a channel's packet after the other channels' of the same
    /// time. A partial packet at the end is dropped.
    func decode(channels: Int, packets: UnsafeRawBufferPointer) -> [Int16]
}

// MARK: - µ-law and A-law

/// G.711 companding: a byte a sample, expanded to 16 bits.
public struct XLawCodec: SoundCodec {

    public enum Law: Hashable, Sendable {
        case mu
        case a
    }

    public let law: Law

    public init(_ law: Law) {
        self.law = law
    }

    public var bytesPerPacket: Int { 1 }
    public var samplesPerPacket: Int { 1 }

    public func decode(channels: Int, packets: UnsafeRawBufferPointer) -> [Int16] {
        let table = law == .mu ? Self.muTable : Self.aTable
        return packets.map { table[Int($0)] }
    }

    /// The 16-bit sample of each µ-law byte.
    static let muTable: [Int16] = (0 ..< 256).map { byte in
        let u = ~UInt8(byte)
        var t = (Int(u & 0x0F) << 3) + 0x84
        t <<= Int(u & 0x70) >> 4
        return Int16(u & 0x80 != 0 ? 0x84 - t : t - 0x84)
    }

    /// The 16-bit sample of each A-law byte.
    static let aTable: [Int16] = (0 ..< 256).map { byte in
        let a = UInt8(byte) ^ 0x55
        var t = Int(a & 0x0F) << 4
        let segment = Int(a & 0x70) >> 4
        switch segment {
        case 0: t += 8
        case 1: t += 0x108
        default:
            t += 0x108
            t <<= segment - 1
        }
        return Int16(a & 0x80 != 0 ? t : -t)
    }
}

// MARK: - IMA4

/// Apple's IMA ADPCM. A channel's packet is 34 bytes of 64 samples: a
/// 16-bit header with the predictor in its top 9 bits and the step index
/// in its low 7, then 32 bytes of 4-bit samples, the low nibble first.
public struct IMA4Codec: SoundCodec {

    public init() {}

    public var bytesPerPacket: Int { 34 }
    public var samplesPerPacket: Int { 64 }

    public func decode(channels: Int, packets: UnsafeRawBufferPointer) -> [Int16] {
        guard channels >= 1 else { return [] }
        let count = packets.count / (34 * channels)
        var samples = [Int16](repeating: 0, count: count * 64 * channels)
        for packet in 0 ..< count {
            for channel in 0 ..< channels {
                let start = (packet * channels + channel) * 34
                let header = Int(packets[start]) << 8 | Int(packets[start + 1])
                var predictor = Int(Int16(bitPattern: UInt16(header & 0xFF80)))
                var index = min(header & 0x7F, 88)
                for byte in 0 ..< 32 {
                    let value = Int(packets[start + 2 + byte])
                    for half in 0 ..< 2 {
                        let nibble = half == 0 ? value & 0x0F : value >> 4
                        let step = Self.steps[index]
                        var difference = step >> 3
                        if nibble & 1 != 0 { difference += step >> 2 }
                        if nibble & 2 != 0 { difference += step >> 1 }
                        if nibble & 4 != 0 { difference += step }
                        predictor += nibble & 8 != 0 ? -difference : difference
                        predictor = min(max(predictor, -32768), 32767)
                        index = min(max(index + Self.adjustments[nibble & 7], 0), 88)
                        samples[(packet * 64 + byte * 2 + half) * channels + channel] = Int16(predictor)
                    }
                }
            }
        }
        return samples
    }

    /// The step sizes of IMA ADPCM, by step index.
    public static let steps: [Int] = [
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
        130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060,
        1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484,
        7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
    ]

    /// How a sample's low three bits move the step index.
    public static let adjustments = [-1, -1, -1, -1, 2, 4, 6, 8]
}
