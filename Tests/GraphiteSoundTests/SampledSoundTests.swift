import struct Foundation.Data
import Testing
import GraphiteBase
import GraphiteSound

@Suite struct SampledSoundTests {

    private func sound(_ encoding: SoundEncoding, channels: Int = 1, bits: Int = 16, count: Int, _ bytes: [UInt8]) -> SampledSound {
        SampledSound(encoding: encoding, sampleRate: 22050, channels: channels, bitsPerSample: bits, count: count, data: bytes)
    }

    @Test func unsignedEightBit() throws {
        let pcm = try sound(.unsigned8, bits: 8, count: 5, [128, 255, 0, 129, 127]).pcm16()
        #expect(pcm == [0, 127 << 8, -32768, 256, -256])
    }

    @Test func signedBigEndianInEveryWidth() throws {
        #expect(try sound(.signedBigEndian, bits: 8, count: 3, [0x00, 0x7F, 0x80]).pcm16() == [0, 0x7F00, -0x8000])
        #expect(try sound(.signedBigEndian, bits: 16, count: 3, [0x00, 0x01, 0x7F, 0xFF, 0x80, 0x00]).pcm16() == [1, 32767, -32768])
        // The top 16 bits of the wider ones.
        #expect(try sound(.signedBigEndian, bits: 24, count: 2, [0x12, 0x34, 0x56, 0xFF, 0xFF, 0xFF]).pcm16() == [0x1234, -1])
        #expect(try sound(.signedBigEndian, bits: 32, count: 2, [0x12, 0x34, 0x56, 0x78, 0x80, 0, 0, 0]).pcm16() == [0x1234, -32768])
    }

    @Test func signedLittleEndianInEveryWidth() throws {
        #expect(try sound(.signedLittleEndian, bits: 16, count: 3, [0x01, 0x00, 0xFF, 0x7F, 0x00, 0x80]).pcm16() == [1, 32767, -32768])
        #expect(try sound(.signedLittleEndian, bits: 8, count: 2, [0x7F, 0x80]).pcm16() == [0x7F00, -0x8000])
        #expect(try sound(.signedLittleEndian, bits: 24, count: 1, [0x56, 0x34, 0x12]).pcm16() == [0x1234])
        #expect(try sound(.signedLittleEndian, bits: 32, count: 1, [0x78, 0x56, 0x34, 0x12]).pcm16() == [0x1234])
    }

    @Test func stereoFramesStayInterleaved() throws {
        let pcm = try sound(.signedBigEndian, channels: 2, count: 2, [0, 1, 0, 2, 0, 3, 0, 4]).pcm16()
        #expect(pcm == [1, 2, 3, 4])
    }

    @Test func compressedSoundsDecode() throws {
        #expect(try sound(.ulaw, count: 3, [0x00, 0x80, 0xFF]).pcm16() == [-32124, 32124, 0])
        #expect(try sound(.alaw, count: 2, [0x55, 0xD5]).pcm16() == [-8, 8])
        var packet = [UInt8](repeating: 0, count: 34)
        packet[2] = 0x77
        let ima = sound(.ima4, count: 1, packet)
        #expect(try ima.pcm16().prefix(2) == [11, 41])
        #expect(ima.frameCount == 64)
    }

    @Test func lessDataThanTheCountSaysGivesTheFramesThereAre() throws {
        #expect(try sound(.signedBigEndian, count: 10, [0, 1, 0, 2, 0, 3, 9]).pcm16() == [1, 2, 3])
        #expect(try sound(.unsigned8, bits: 8, count: 100, [128, 129]).pcm16() == [0, 256])
        #expect(try sound(.ulaw, count: 9, [0x00]).pcm16() == [-32124])
        #expect(try sound(.signedBigEndian, count: 0, [1, 2, 3, 4]).pcm16().isEmpty)
        // One whole packet of the two the count says; the stray bytes after it are dropped.
        #expect(try sound(.ima4, count: 2, [UInt8](repeating: 0, count: 40)).pcm16().count == 64)
        #expect(try sound(.ima4, count: 2, [UInt8](repeating: 0, count: 33)).pcm16().isEmpty)
    }

    @Test func badSoundsAreBadFormat() {
        #expect(throws: MacError.badFormat) { try sound(.signedBigEndian, channels: 0, count: 1, [0, 0]).pcm16() }
        #expect(throws: MacError.badFormat) { try sound(.signedBigEndian, bits: 12, count: 1, [0, 0]).pcm16() }
        #expect(throws: MacError.badFormat) { try sound(.unsigned8, bits: 16, count: 1, [0, 0]).pcm16() }
        #expect(throws: MacError.badFormat) { try sound(.signedLittleEndian, count: -1, [0, 0]).pcm16() }
    }

    @Test func maceIsNotDecodedYet() {
        #expect(throws: MacError.unimplemented) { try sound(.mace3, count: 1, [0, 0]).pcm16() }
        #expect(throws: MacError.unimplemented) { try sound(.mace6, count: 1, [0]).pcm16() }
        #expect(sound(.mace3, count: 4, []).frameCount == 24)
        #expect(sound(.mace6, count: 4, []).frameCount == 24)
    }

    @Test func durationFollowsTheFrames() {
        #expect(sound(.signedBigEndian, count: 22050, []).duration == 1)
        #expect(sound(.ima4, count: 1, []).duration == 64.0 / 22050)
        let silent = SampledSound(encoding: .unsigned8, sampleRate: 0, channels: 1, bitsPerSample: 8, count: 10, data: [UInt8]())
        #expect(silent.duration == 0)
    }

    @Test func hostileCountsDontTrap() throws {
        // Products of counts that overflow even a 64-bit Int stop at the data.
        let huge = sound(.signedBigEndian, channels: 256, count: .max, [0, 1, 0, 2])
        #expect(try huge.pcm16() == [1, 2])
        #expect(huge.frameCount == Int.max)
        let packets = sound(.ima4, channels: 256, count: .max, [UInt8](repeating: 0, count: 34))
        #expect(try packets.pcm16().isEmpty)
        #expect(sound(.mace3, count: .max, []).frameCount == .max)
    }

    @Test func dataIsKeptAsGivenIncludingSlices() throws {
        let whole = Data([9, 9, 0, 1, 0, 2, 8])
        let slice = whole[2 ..< 6]
        let sound = SampledSound(encoding: .signedBigEndian, sampleRate: 8000, channels: 1, bitsPerSample: 16, count: 2, data: slice)
        #expect(sound.data.startIndex == 2)
        #expect(try sound.pcm16() == [1, 2])
        let fromBuffer = try [UInt8]([0, 5]).withUnsafeBytes {
            try SampledSound(encoding: .signedBigEndian, sampleRate: 8000, channels: 1, bitsPerSample: 16, count: 1, data: $0).pcm16()
        }
        #expect(fromBuffer == [5])
    }
}
