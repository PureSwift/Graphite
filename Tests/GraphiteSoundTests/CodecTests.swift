import Foundation
import Testing
import GraphiteBase
import GraphiteSound

@Suite struct CodecTests {

    private func decode(_ codec: some SoundCodec, channels: Int = 1, _ bytes: [UInt8]) -> [Int16] {
        bytes.withUnsafeBytes { codec.decode(channels: channels, packets: $0) }
    }

    // MARK: µ-law and A-law

    @Test func muLawMatchesG711() {
        let codec = XLawCodec(.mu)
        // The first and last of the positive half, and their mirrors.
        #expect(decode(codec, [0x00, 0x01, 0x0F, 0x10, 0x7E, 0x7F]) == [-32124, -31100, -16764, -15996, -8, 0])
        #expect(decode(codec, [0x80, 0x81, 0x8F, 0x90, 0xFE, 0xFF]) == [32124, 31100, 16764, 15996, 8, 0])
    }

    @Test func aLawMatchesG711() {
        let codec = XLawCodec(.a)
        #expect(decode(codec, [0x00, 0x01, 0x02, 0x08, 0x55, 0x7F]) == [-5504, -5248, -6016, -7552, -8, -848])
        #expect(decode(codec, [0x80, 0x81, 0xD5, 0xFF]) == [5504, 5248, 8, 848])
    }

    @Test func everyByteIsTheNegativeOfItsMirror() {
        for law in [XLawCodec.Law.mu, .a] {
            let codec = XLawCodec(law)
            let all = decode(codec, (0 ... 255).map(UInt8.init))
            #expect(all.count == 256)
            for byte in 0 ..< 128 { #expect(all[byte] == -all[byte + 128]) }
        }
    }

    @Test func muLawIsMonotonicInItsMagnitude() {
        let all = decode(XLawCodec(.mu), (0 ... 127).map(UInt8.init))
        #expect(all == all.sorted())
        #expect(all.first == -32124 && all.last == 0)
    }

    @Test func xlawIgnoresChannels() {
        let codec = XLawCodec(.mu)
        #expect(decode(codec, channels: 2, [0x00, 0x80]) == [-32124, 32124])
        #expect(codec.bytesPerPacket == 1 && codec.samplesPerPacket == 1)
        #expect(decode(codec, []).isEmpty)
    }

    // MARK: IMA4

    /// IMA4 as an encoder makes it, for the tests: the reconstruction a decoder
    /// should give, and the bytes of packets, interleaved over channels.
    private func encodeIMA4(_ channels: [[Int16]]) -> (bytes: [UInt8], reconstructed: [[Int16]]) {
        let steps = IMA4Codec.steps
        let adjustments = IMA4Codec.adjustments
        var bytes: [UInt8] = []
        var reconstructed = channels.map { _ in [Int16]() }
        var indices = [Int](repeating: 0, count: channels.count)
        for block in 0 ..< channels[0].count / 64 {
            for (channel, samples) in channels.enumerated() {
                let slice = samples[block * 64 ..< (block + 1) * 64]
                var predictor = min(max((Int(slice.first!) + 64) / 128 * 128, -32768), 32640)
                var index = indices[channel]
                let header = UInt16(truncatingIfNeeded: predictor) & 0xFF80 | UInt16(index)
                bytes.append(UInt8(header >> 8))
                bytes.append(UInt8(header & 0xFF))
                var nibbles: [UInt8] = []
                for sample in slice {
                    var difference = Int(sample) - predictor
                    var nibble = 0
                    if difference < 0 {
                        nibble = 8
                        difference = -difference
                    }
                    var step = steps[index]
                    if difference >= step { nibble |= 4; difference -= step }
                    step >>= 1
                    if difference >= step { nibble |= 2; difference -= step }
                    step >>= 1
                    if difference >= step { nibble |= 1 }
                    // The decoder's own arithmetic, so what it gives is known.
                    let full = steps[index]
                    var delta = full >> 3
                    if nibble & 1 != 0 { delta += full >> 2 }
                    if nibble & 2 != 0 { delta += full >> 1 }
                    if nibble & 4 != 0 { delta += full }
                    predictor = min(max(predictor + (nibble & 8 != 0 ? -delta : delta), -32768), 32767)
                    index = min(max(index + adjustments[nibble & 7], 0), 88)
                    nibbles.append(UInt8(nibble))
                    reconstructed[channel].append(Int16(predictor))
                }
                indices[channel] = index
                for pair in stride(from: 0, to: 64, by: 2) { bytes.append(nibbles[pair] | nibbles[pair + 1] << 4) }
            }
        }
        return (bytes, reconstructed)
    }

    private func sine(_ count: Int, amplitude: Double, period: Double, phase: Double = 0) -> [Int16] {
        (0 ..< count).map { index -> Int16 in
            let angle = Double(index) / period * 2 * Double.pi + phase
            return Int16(amplitude * Foundation.sin(angle))
        }
    }

    @Test func decodesByTheStepTable() {
        // Header 0: predictor 0, step index 0. A nibble of 7 adds the step's
        // 7/8 and the step index moves by 8: 7, then 16, then 34.
        var packet = [UInt8](repeating: 0, count: 34)
        packet[2] = 0x77
        packet[3] = 0x77
        let samples = decode(IMA4Codec(), packet)
        #expect(samples.count == 64)
        // The fourth: index 24, a step of 73, adds 9 + 18 + 36 + 73.
        #expect(Array(samples.prefix(4)) == [11, 41, 104, 240])
    }

    @Test func theHeaderGivesPredictorAndIndex() {
        // Predictor 0x2000 (the top 9 bits of the header), index 0. A nibble of
        // 8 is a negative zero difference and lowers the index, which stays 0.
        var packet = [UInt8](repeating: 0x88, count: 34)
        packet[0] = 0x20
        packet[1] = 0x00
        #expect(decode(IMA4Codec(), packet) == [Int16](repeating: 0x2000, count: 64))
        // The low 7 bits are the index, up to 88; more are clamped to it.
        var clamped = [UInt8](repeating: 0, count: 34)
        clamped[1] = 0x7F
        #expect(decode(IMA4Codec(), clamped).count == 64)
    }

    @Test func theStepTableIsIMAs() {
        let steps = IMA4Codec.steps
        #expect(steps.count == 89)
        #expect(steps.first == 7 && steps.last == 32767)
        #expect(steps == steps.sorted())
        // Each step is about a tenth more than the one before, past the first few.
        for index in 16 ..< 88 {
            let ratio = Double(steps[index + 1]) / Double(steps[index])
            #expect(ratio > 1.08 && ratio < 1.12, "step \(index)")
        }
        #expect(IMA4Codec.adjustments == [-1, -1, -1, -1, 2, 4, 6, 8])
    }

    @Test func nibblesAreLowFirst() {
        var packet = [UInt8](repeating: 0, count: 34)
        packet[2] = 0x70   // low nibble 0, high nibble 7
        let samples = decode(IMA4Codec(), packet)
        #expect(samples[0] == 0)
        #expect(samples[1] == 11)
    }

    @Test func roundTripsASineWave() {
        let wave = sine(640, amplitude: 8000, period: 50)
        let (bytes, reconstructed) = encodeIMA4([wave])
        #expect(bytes.count == 10 * 34)
        let decoded = decode(IMA4Codec(), bytes)
        #expect(decoded == reconstructed[0])
        var sumOfSquares = 0.0
        for (got, wanted) in zip(decoded, wave) {
            let difference = Double(Int(got) - Int(wanted))
            sumOfSquares += difference * difference
        }
        let rms = (sumOfSquares / Double(wave.count)).squareRoot()
        #expect(rms < 400)
    }

    @Test func channelsAreInterleavedFromTheirPackets() {
        let left = sine(128, amplitude: 6000, period: 40)
        let right = sine(128, amplitude: 3000, period: 25, phase: 1)
        let (bytes, reconstructed) = encodeIMA4([left, right])
        let decoded = decode(IMA4Codec(), channels: 2, bytes)
        #expect(decoded.count == 256)
        #expect(stride(from: 0, to: 256, by: 2).map { decoded[$0] } == reconstructed[0])
        #expect(stride(from: 1, to: 256, by: 2).map { decoded[$0] } == reconstructed[1])
    }

    @Test func aPartialPacketIsDropped() {
        let (bytes, reconstructed) = encodeIMA4([sine(64, amplitude: 5000, period: 30)])
        #expect(decode(IMA4Codec(), bytes + [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) == reconstructed[0])
        #expect(decode(IMA4Codec(), Array(bytes.prefix(33))).isEmpty)
        #expect(decode(IMA4Codec(), channels: 0, bytes).isEmpty)
        #expect(IMA4Codec().bytesPerPacket == 34 && IMA4Codec().samplesPerPacket == 64)
    }

    @Test func extremesStayInRange() {
        // Every nibble the largest step up, and then down: no overflow.
        let up = decode(IMA4Codec(), [0x7F, 0x00] + [UInt8](repeating: 0x77, count: 32))
        #expect(up.max()! <= 32767)
        let down = decode(IMA4Codec(), [0x80, 0x00] + [UInt8](repeating: 0xFF, count: 32))
        #expect(down.min()! >= -32768)
    }

    // MARK: Encodings

    @Test func compressionTypesRoundTrip() {
        for encoding in [SoundEncoding.unsigned8, .signedBigEndian, .signedLittleEndian, .ulaw, .alaw, .ima4, .mace3, .mace6] {
            #expect(SoundEncoding(compressionType: encoding.compressionType) == encoding)
        }
        #expect(SoundEncoding(compressionType: "NONE") == .signedBigEndian)
        #expect(SoundEncoding(compressionType: "fl32") == nil)
        #expect(SoundEncoding(compressionType: "zzzz") == nil)
    }

    @Test func packetsAndCodecs() {
        #expect(SoundEncoding.ima4.packet?.bytes == 34 && SoundEncoding.ima4.packet?.frames == 64)
        #expect(SoundEncoding.mace3.packet?.bytes == 2 && SoundEncoding.mace3.packet?.frames == 6)
        #expect(SoundEncoding.mace6.packet?.bytes == 1 && SoundEncoding.mace6.packet?.frames == 6)
        #expect(SoundEncoding.ulaw.isCompressed && SoundEncoding.ima4.isCompressed && SoundEncoding.mace3.isCompressed)
        #expect(!SoundEncoding.unsigned8.isCompressed && !SoundEncoding.signedLittleEndian.isCompressed)
        #expect(SoundEncoding.ima4.codec is IMA4Codec)
        #expect((SoundEncoding.ulaw.codec as? XLawCodec)?.law == .mu)
        #expect((SoundEncoding.alaw.codec as? XLawCodec)?.law == .a)
        #expect(SoundEncoding.mace3.codec == nil && SoundEncoding.unsigned8.codec == nil)
    }
}
