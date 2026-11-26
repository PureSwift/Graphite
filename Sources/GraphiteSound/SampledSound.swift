// A sampled sound: what a 'snd ' resource's sampled sound header and an
// AIFF file both describe: samples and how to read them.

import protocol Foundation.ContiguousBytes
import struct Foundation.Data
import GraphiteBase

public struct SampledSound: Hashable, Sendable {

    public var encoding: SoundEncoding

    /// Samples a second.
    public var sampleRate: Double

    public var channels: Int

    /// The bits of an uncompressed sample (8, 16, 24 or 32); 16 for a
    /// compressed one, which decodes to that.
    public var bitsPerSample: Int

    /// The sample frames of an uncompressed sound; the packets of a
    /// compressed one.
    public var count: Int

    /// The samples as they are stored. It may be a slice of the resource or
    /// file it came from, and so need not start at index 0.
    public var data: Data

    /// The MIDI note the sound plays at its own rate, 60 for middle C.
    public var baseNote: Int

    /// The sample frames to repeat, from the loop's start to its end.
    public var loop: Range<Int>?

    public init(encoding: SoundEncoding, sampleRate: Double, channels: Int, bitsPerSample: Int, count: Int,
                data: some ContiguousBytes, baseNote: Int = 60, loop: Range<Int>? = nil) {
        self.encoding = encoding
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
        self.count = count
        self.data = Data(sharing: data)
        self.baseNote = baseNote
        self.loop = loop
    }

    /// The sample frames the sound plays for: its count, or its packets'
    /// worth.
    public var frameCount: Int {
        Self.product(count, encoding.packet?.frames ?? 1)
    }

    /// Seconds.
    public var duration: Double {
        sampleRate > 0 ? Double(frameCount) / sampleRate : 0
    }

    /// The samples as 16-bit signed integers, one frame's channels after
    /// another. A sound with less data than its count says gives the frames
    /// there are. `badFormat` for no channels or an odd sample size, and
    /// `unimplemented` for MACE.
    public func pcm16() throws(MacError) -> [Int16] {
        guard channels >= 1, count >= 0 else { throw .badFormat }
        switch encoding {
        case .mace3, .mace6:
            throw .unimplemented
        case .unsigned8:
            guard bitsPerSample == 8 else { throw .badFormat }
        case .signedBigEndian, .signedLittleEndian:
            guard [8, 16, 24, 32].contains(bitsPerSample) else { throw .badFormat }
        case .ulaw, .alaw, .ima4:
            break
        }
        return data.withUnsafeBytes { raw in
            if let codec = encoding.codec, let packet = encoding.packet {
                let needed = Self.product(Self.product(count, packet.bytes), channels)
                return codec.decode(channels: channels, packets: UnsafeRawBufferPointer(rebasing: raw[..<min(raw.count, needed)]))
            }
            let width = encoding == .unsigned8 ? 1 : bitsPerSample / 8
            let total = min(Self.product(count, channels), raw.count / width)
            var samples = [Int16](repeating: 0, count: total)
            for index in 0 ..< total {
                let at = index * width
                switch encoding {
                case .unsigned8:
                    samples[index] = Int16((Int(raw[at]) - 128) << 8)
                case .signedBigEndian:
                    samples[index] = width == 1 ? Int16(Int8(bitPattern: raw[at])) << 8
                        : Int16(bitPattern: UInt16(raw[at]) << 8 | UInt16(raw[at + 1]))
                default:
                    samples[index] = width == 1 ? Int16(Int8(bitPattern: raw[at])) << 8
                        : Int16(bitPattern: UInt16(raw[at + width - 1]) << 8 | UInt16(raw[at + width - 2]))
                }
            }
            return samples
        }
    }

    /// A product that stops at the largest Int, so that a count a hostile
    /// resource gives can't overflow on a 32-bit CPU.
    private static func product(_ a: Int, _ b: Int) -> Int {
        let (value, overflow) = a.multipliedReportingOverflow(by: b)
        return overflow ? Int.max : value
    }
}

extension Data {

    /// A Data of any contiguous bytes: the same one if they are, so a slice
    /// of a mapped file stays a slice of it.
    init(sharing bytes: some ContiguousBytes) {
        self = bytes as? Data ?? bytes.withUnsafeBytes { Data($0) }
    }
}
