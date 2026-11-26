import struct Foundation.Data
import Testing
import GraphiteBase
import GraphiteSound

@Suite struct SoundResourceTests {

    // MARK: Fixtures, built from the layouts in Inside Macintosh: Sound

    /// The 22 bytes every sampled sound header begins with.
    private func baseHeader(length: Int32, rate: UInt32, loopStart: UInt32 = 0, loopEnd: UInt32 = 0, encode: UInt8, baseNote: UInt8 = 60) -> BigEndianWriter {
        var writer = BigEndianWriter()
        writer.write(UInt32(0))
        writer.write(length)
        writer.write(rate)
        writer.write(loopStart)
        writer.write(loopEnd)
        writer.write(encode)
        writer.write(baseNote)
        return writer
    }

    private let rate22k: UInt32 = 0x56EE_8BA3    // rate22khz, 22254.545…
    private let rate44k: UInt32 = 44100 << 16

    private func standard(_ samples: [UInt8], loopStart: UInt32 = 0, loopEnd: UInt32 = 0) -> [UInt8] {
        var writer = baseHeader(length: Int32(samples.count), rate: rate22k, loopStart: loopStart, loopEnd: loopEnd, encode: 0x00)
        writer.write(bytes: samples)
        return writer.bytes
    }

    private func extended(channels: Int32, frames: Int32, bits: Int16, samples: [UInt8]) -> [UInt8] {
        var writer = baseHeader(length: channels, rate: rate44k, encode: 0xFF)
        writer.write(frames)
        writer.write(bytes: Extended80(44100).bytes)
        writer.writeZeros(4 + 4 + 4)
        writer.write(bits)
        writer.writeZeros(14)
        writer.write(bytes: samples)
        return writer.bytes
    }

    private func compressed(channels: Int32, packets: Int32, type: FourCharCode?, samples: [UInt8]) -> [UInt8] {
        var writer = baseHeader(length: channels, rate: rate44k, encode: 0xFE)
        writer.write(packets)
        writer.writeZeros(10 + 4)
        writer.write(type?.rawValue ?? 0)
        writer.writeZeros(20)
        writer.write(bytes: samples)
        return writer.bytes
    }

    /// A format 1 resource with a sampled synthesizer and one bufferCmd.
    private func format1(_ header: [UInt8], initBits: UInt32 = 0x0080) -> [UInt8] {
        var writer = BigEndianWriter()
        writer.write(UInt16(1))
        writer.write(UInt16(1))
        writer.write(UInt16(5))
        writer.write(initBits)
        writer.write(UInt16(1))
        writer.write(UInt16(0x8051))
        writer.write(UInt16(0))
        writer.write(UInt32(20))
        writer.write(bytes: header)
        return writer.bytes
    }

    /// A format 2 resource: a reference count and one soundCmd.
    private func format2(_ header: [UInt8]) -> [UInt8] {
        var writer = BigEndianWriter()
        writer.write(UInt16(2))
        writer.write(UInt16(0x1234))
        writer.write(UInt16(1))
        writer.write(UInt16(0x8050))
        writer.write(UInt16(0))
        writer.write(UInt32(14))
        writer.write(bytes: header)
        return writer.bytes
    }

    // MARK: Reading

    @Test func standardHeaders() throws {
        let sound = try SampledSound(snd: format1(standard([128, 255, 0, 128])))
        #expect(sound.encoding == .unsigned8 && sound.channels == 1 && sound.bitsPerSample == 8 && sound.count == 4)
        #expect(abs(sound.sampleRate - 22254.545) < 0.01)
        #expect(sound.baseNote == 60 && sound.loop == nil)
        #expect(try sound.pcm16() == [0, 127 << 8, -32768, 0])
    }

    @Test func format2ResourcesToo() throws {
        let sound = try SampledSound(snd: format2(standard([200, 100])))
        #expect(try sound.pcm16() == [72 << 8, -28 << 8])
        #expect(try SoundResource.headerOffset(in: format2(standard([]))) == 14)
        #expect(try SoundResource.headerOffset(in: format1(standard([]))) == 20)
    }

    @Test func extendedHeaders() throws {
        let sound = try SampledSound(snd: format1(extended(channels: 2, frames: 3, bits: 16,
                                                           samples: [0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6]), initBits: 0x00C0))
        #expect(sound.encoding == .signedBigEndian && sound.channels == 2 && sound.bitsPerSample == 16 && sound.count == 3)
        #expect(sound.sampleRate == 44100)
        #expect(try sound.pcm16() == [1, 2, 3, 4, 5, 6])
        // Eight bits, in an extended header, are unsigned.
        let eight = try SampledSound(header: extended(channels: 1, frames: 2, bits: 8, samples: [128, 255]))
        #expect(eight.encoding == .unsigned8)
        #expect(try eight.pcm16() == [0, 127 << 8])
    }

    @Test func compressedHeaders() throws {
        let ulaw = try SampledSound(snd: format1(compressed(channels: 1, packets: 3, type: "ulaw", samples: [0x00, 0x80, 0xFF])))
        #expect(ulaw.encoding == .ulaw && ulaw.bitsPerSample == 16 && ulaw.count == 3 && ulaw.frameCount == 3)
        #expect(try ulaw.pcm16() == [-32124, 32124, 0])
        var packet = [UInt8](repeating: 0, count: 34)
        packet[2] = 0x77
        let ima = try SampledSound(header: compressed(channels: 1, packets: 1, type: "ima4", samples: packet))
        #expect(ima.encoding == .ima4 && ima.frameCount == 64)
        #expect(try ima.pcm16().prefix(2) == [11, 41])
    }

    @Test func noCompressionTypeIsMACEOfTheResourcesInitBits() throws {
        let header = compressed(channels: 1, packets: 2, type: nil, samples: [1, 2, 3, 4])
        #expect(try SampledSound(snd: format1(header, initBits: 0x0080 | 0x0300)).encoding == .mace3)
        #expect(try SampledSound(snd: format1(header, initBits: 0x0080 | 0x0400)).encoding == .mace6)
        #expect(try SampledSound(header: header).encoding == .mace3)
        #expect(try SampledSound(header: header).frameCount == 12)
    }

    @Test func unknownCompressionIsInvalid() {
        #expect(throws: MacError.invalidCompression) { try SampledSound(header: compressed(channels: 1, packets: 1, type: "zzzz", samples: [0])) }
        // An uncompressed type isn't a compression a compressed header names.
        #expect(throws: MacError.invalidCompression) { try SampledSound(header: compressed(channels: 1, packets: 1, type: "twos", samples: [0])) }
    }

    @Test func loopsAndBaseNotes() throws {
        let looped = try SampledSound(header: standard([1, 2, 3, 4, 5, 6], loopStart: 2, loopEnd: 5))
        #expect(looped.loop == 2 ..< 5)
        #expect(try SampledSound(header: standard([1, 2], loopStart: 0, loopEnd: 0)).loop == nil)
        #expect(try SampledSound(header: standard([1, 2], loopStart: 5, loopEnd: 3)).loop == nil)
        var writer = baseHeader(length: 2, rate: rate22k, encode: 0, baseNote: 72)
        writer.write(bytes: [1, 2])
        #expect(try SampledSound(header: writer.bytes).baseNote == 72)
    }

    @Test func lessDataThanTheHeaderSaysIsWhatThereIs() throws {
        var writer = baseHeader(length: 100, rate: rate22k, encode: 0)
        writer.write(bytes: [128, 129, 130])
        let sound = try SampledSound(header: writer.bytes)
        #expect(sound.count == 100)
        #expect(sound.data.count == 3)
        #expect(try sound.pcm16() == [0, 256, 512])
    }

    @Test func headerOffsetFailures() {
        #expect(throws: MacError.badFormat) { try SoundResource.headerOffset(in: [UInt8]()) }
        #expect(throws: MacError.badFormat) { try SoundResource.headerOffset(in: [0, 3, 0, 0]) }
        // Format 1 with a synthesizer that isn't sampledSynth.
        var squareWave = BigEndianWriter()
        squareWave.write(UInt16(1)); squareWave.write(UInt16(1)); squareWave.write(UInt16(1)); squareWave.write(UInt32(0))
        squareWave.write(UInt16(1)); squareWave.write(UInt16(0x8051)); squareWave.write(UInt16(0)); squareWave.write(UInt32(20))
        squareWave.writeZeros(40)
        #expect(throws: MacError.badFormat) { try SoundResource.headerOffset(in: squareWave.bytes) }
        // No commands, a command without sound data, and an offset past the end.
        var none = format1(standard([1]))
        none[10] = 0
        none[11] = 0
        #expect(throws: MacError.badFormat) { try SoundResource.headerOffset(in: none) }
        var noOffsetBit = format1(standard([1]))
        noOffsetBit[12] = 0x00
        #expect(throws: MacError.badFormat) { try SoundResource.headerOffset(in: noOffsetBit) }
        var past = format1(standard([1]))
        past[18] = 0xFF
        #expect(throws: MacError.badFormat) { try SoundResource.headerOffset(in: past) }
    }

    @Test func headerFailures() {
        #expect(throws: MacError.badFormat) { try SampledSound(header: [UInt8]()) }
        #expect(throws: MacError.badFormat) { try SampledSound(header: [UInt8](repeating: 0, count: 21)) }
        // A samplePtr that isn't zero, and an encoding that isn't a header's.
        var pointer = standard([1])
        pointer[3] = 1
        #expect(throws: MacError.badFormat) { try SampledSound(header: pointer) }
        var other = standard([1])
        other[20] = 0x42
        #expect(throws: MacError.badFormat) { try SampledSound(header: other) }
        // No channels, and a negative count.
        #expect(throws: MacError.badFormat) { try SampledSound(header: extended(channels: 0, frames: 1, bits: 16, samples: [0, 0])) }
        #expect(throws: MacError.badFormat) { try SampledSound(header: extended(channels: 1, frames: -1, bits: 16, samples: [0, 0])) }
        #expect(throws: MacError.badFormat) { try SampledSound(header: extended(channels: 1000, frames: 1, bits: 16, samples: [0, 0])) }
    }

    @Test func hostileSizesDontTrap() throws {
        let huge = try SampledSound(header: extended(channels: 256, frames: .max, bits: 32, samples: [0, 1, 0, 0]))
        #expect(huge.data.count == 4)
        #expect(try huge.pcm16() == [1])
        let packets = try SampledSound(header: compressed(channels: 256, packets: .max, type: "ima4", samples: []))
        #expect(packets.data.isEmpty)
    }

    // MARK: Sources of bytes

    @Test func resourcesFromAnyBytes() throws {
        let bytes = format1(standard([128, 129]))
        #expect(try SampledSound(snd: Data(bytes)).count == 2)
        #expect(try SampledSound(snd: Data([7, 7, 7] + bytes)[3...]).count == 2)
        #expect(try bytes.withUnsafeBytes { try SampledSound(snd: $0) }.count == 2)
        #expect(try SoundResource.headerOffset(in: Data([1, 2] + bytes)[2...]) == 20)
    }

    @Test func samplesAreASliceOfTheResource() throws {
        let resource = Data(format1(standard([128, 129, 130])))
        let sound = try SampledSound(snd: resource)
        // After the 20 bytes and the 22 of header; not copied.
        #expect(sound.data.startIndex == 42)
        #expect(Array(sound.data) == [128, 129, 130])
    }

    // MARK: Writing

    @Test func writtenResourcesReadBack() throws {
        let original = SampledSound(encoding: .unsigned8, sampleRate: 22254.545, channels: 1, bitsPerSample: 8, count: 4,
                                    data: [128, 255, 0, 128], baseNote: 64, loop: 1 ..< 3)
        let bytes = original.sndResource
        #expect(try SoundResource.headerOffset(in: bytes) == 20)
        #expect(bytes.count == 20 + 22 + 4)
        let again = try SampledSound(snd: bytes)
        #expect(again.encoding == .unsigned8 && again.count == 4 && again.baseNote == 64 && again.loop == 1 ..< 3)
        #expect(abs(again.sampleRate - original.sampleRate) < 0.001)
        #expect(Array(again.data) == [128, 255, 0, 128])
    }

    @Test func writtenStereoSixteenBitUsesTheExtendedHeader() throws {
        let original = SampledSound(encoding: .signedBigEndian, sampleRate: 44100, channels: 2, bitsPerSample: 16, count: 2,
                                    data: [0, 1, 0, 2, 0, 3, 0, 4])
        let bytes = original.sndResource
        #expect(bytes.count == 20 + 64 + 8)
        // initStereo in the init bits, then the extended encoding in the header.
        #expect(Array(bytes[6 ..< 10]) == [0, 0, 0, 0xC0])
        #expect(bytes[20 + 20] == 0xFF)
        let again = try SampledSound(snd: bytes)
        #expect(again.encoding == .signedBigEndian && again.channels == 2 && again.bitsPerSample == 16 && again.sampleRate == 44100)
        #expect(try again.pcm16() == [1, 2, 3, 4])
    }

    @Test func writtenCompressedSoundsUseTheCompressedHeader() throws {
        for encoding in [SoundEncoding.ulaw, .alaw, .mace3, .mace6] {
            let original = SampledSound(encoding: encoding, sampleRate: 11025, channels: 1, bitsPerSample: 16, count: 3, data: [1, 2, 3, 4, 5, 6])
            let bytes = original.sndResource
            #expect(bytes[20 + 20] == 0xFE)
            let again = try SampledSound(snd: bytes)
            #expect(again.encoding == encoding && again.count == 3)
        }
        // MACE says which in the resource's init bits.
        let mace6 = SampledSound(encoding: .mace6, sampleRate: 11025, channels: 1, bitsPerSample: 16, count: 1, data: [1])
        #expect(Array(mace6.sndResource[6 ..< 10]) == [0, 0, 0x04, 0x80])
    }

    // MARK: Damage

    @Test func truncatedResourcesNeverTrap() {
        let resources = [
            format1(standard([128, 129, 130])),
            format1(extended(channels: 2, frames: 2, bits: 16, samples: [0, 1, 0, 2, 0, 3, 0, 4])),
            format2(compressed(channels: 1, packets: 2, type: "ulaw", samples: [1, 2])),
        ]
        for resource in resources {
            for length in 0 ... resource.count {
                if let sound = try? SampledSound(snd: resource.prefix(length)) { _ = try? sound.pcm16() }
                _ = try? SoundResource.headerOffset(in: resource.prefix(length))
            }
        }
    }

    @Test func damagedBytesNeverTrap() {
        var generator = QuickDrawRandom(seed: 7)
        let original = format1(extended(channels: 2, frames: 2, bits: 16, samples: [0, 1, 0, 2, 0, 3, 0, 4]))
        for _ in 0 ..< 400 {
            var bytes = original
            for _ in 0 ..< 4 { bytes[Int(UInt16(bitPattern: generator.next())) % bytes.count] = UInt8(truncatingIfNeeded: generator.next()) }
            if let sound = try? SampledSound(snd: bytes) { _ = try? sound.pcm16() }
        }
    }
}
