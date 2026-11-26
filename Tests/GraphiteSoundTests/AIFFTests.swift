import struct Foundation.Data
import Testing
import GraphiteBase
import GraphiteSound

@Suite struct AIFFTests {

    // MARK: Fixtures, from the AIFF and AIFF-C specifications

    private func chunk(_ id: FourCharCode, _ body: [UInt8]) -> [UInt8] {
        var writer = BigEndianWriter()
        writer.write(id.rawValue)
        writer.write(UInt32(body.count))
        writer.write(bytes: body)
        if body.count % 2 == 1 { writer.write(UInt8(0)) }
        return writer.bytes
    }

    /// An AIFF file of chunks.
    private func file(_ chunks: [[UInt8]]) -> [UInt8] { form("AIFF", chunks) }

    /// An AIFF-C file of chunks.
    private func aifc(_ chunks: [[UInt8]]) -> [UInt8] { form("AIFC", chunks) }

    private func form(_ form: FourCharCode, _ chunks: [[UInt8]]) -> [UInt8] {
        var body = BigEndianWriter()
        body.write(form.rawValue)
        for chunk in chunks { body.write(bytes: chunk) }
        var writer = BigEndianWriter()
        writer.write(FourCharCode("FORM").rawValue)
        writer.write(UInt32(body.count))
        writer.write(bytes: body.bytes)
        return writer.bytes
    }

    private func common(channels: UInt16 = 1, frames: UInt32, bits: UInt16 = 16, rate: Double = 44100, compression: FourCharCode? = nil) -> [UInt8] {
        var writer = BigEndianWriter()
        writer.write(channels)
        writer.write(frames)
        writer.write(bits)
        writer.write(bytes: Extended80(rate).bytes)
        if let compression {
            writer.write(compression.rawValue)
            // The name, a Pascal string padded to an even length.
            writer.write(bytes: [4, 0x74, 0x65, 0x73, 0x74, 0])
        }
        return chunk("COMM", writer.bytes)
    }

    private func soundData(_ samples: [UInt8], offset: UInt32 = 0, padding: Int = 0) -> [UInt8] {
        var writer = BigEndianWriter()
        writer.write(offset)
        writer.write(UInt32(0))
        writer.writeZeros(padding)
        writer.write(bytes: samples)
        return chunk("SSND", writer.bytes)
    }

    private func markers(_ markers: [(UInt16, UInt32, String)]) -> [UInt8] {
        var writer = BigEndianWriter()
        writer.write(UInt16(markers.count))
        for (id, position, name) in markers {
            writer.write(id)
            writer.write(position)
            let bytes = Array(name.utf8)
            writer.write(UInt8(bytes.count))
            writer.write(bytes: bytes)
            if (bytes.count + 1) % 2 == 1 { writer.write(UInt8(0)) }
        }
        return chunk("MARK", writer.bytes)
    }

    private func instrument(baseNote: Int8 = 60, playMode: UInt16, begin: UInt16, end: UInt16) -> [UInt8] {
        var writer = BigEndianWriter()
        writer.write(baseNote)
        writer.write(bytes: [0, 0, 127, 1, 127])       // detune, low and high note, low and high velocity
        writer.write(Int16(0))                         // gain
        writer.write(playMode)
        writer.write(begin)
        writer.write(end)
        writer.write(bytes: [0, 0, 0, 0, 0, 0])        // the release loop
        return chunk("INST", writer.bytes)
    }

    // MARK: Reading

    @Test func aStereoSixteenBitFile() throws {
        let aiff = file([common(channels: 2, frames: 2, bits: 16), soundData([0, 1, 0, 2, 0, 3, 0, 4])])
        let sound = try SampledSound(aiff: aiff)
        #expect(sound.encoding == .signedBigEndian && sound.channels == 2 && sound.bitsPerSample == 16 && sound.count == 2)
        #expect(sound.sampleRate == 44100 && sound.baseNote == 60 && sound.loop == nil)
        #expect(try sound.pcm16() == [1, 2, 3, 4])
    }

    @Test func eightBitAIFFIsSigned() throws {
        let sound = try SampledSound(aiff: file([common(frames: 3, bits: 8), soundData([0, 0x7F, 0x80])]))
        #expect(sound.encoding == .signedBigEndian && sound.bitsPerSample == 8)
        #expect(try sound.pcm16() == [0, 0x7F00, -0x8000])
    }

    @Test func sampleRates() throws {
        for rate in [8000.0, 11025, 22050, 22254.545, 44100, 48000, 96000] {
            let sound = try SampledSound(aiff: file([common(frames: 1, rate: rate), soundData([0, 0])]))
            #expect(abs(sound.sampleRate - rate) < 1e-9)
        }
    }

    @Test func aifcCompressionTypes() throws {
        let cases: [(FourCharCode, SoundEncoding)] = [
            ("NONE", .signedBigEndian), ("twos", .signedBigEndian), ("sowt", .signedLittleEndian), ("raw ", .unsigned8),
            ("ulaw", .ulaw), ("alaw", .alaw), ("ima4", .ima4), ("MAC3", .mace3), ("MAC6", .mace6),
        ]
        for (type, encoding) in cases {
            let sound = try SampledSound(aiff: aifc([common(frames: 1, compression: type), soundData([0, 0])]))
            #expect(sound.encoding == encoding, "\(type)")
        }
        #expect(try SampledSound(aiff: aifc([common(frames: 1, bits: 16, compression: "ima4"), soundData([0])])).bitsPerSample == 16)
    }

    @Test func littleEndianAIFC() throws {
        let sound = try SampledSound(aiff: aifc([common(frames: 2, compression: "sowt"), soundData([1, 0, 0xFF, 0x7F])]))
        #expect(try sound.pcm16() == [1, 32767])
    }

    @Test func ulawAIFC() throws {
        let sound = try SampledSound(aiff: aifc([common(frames: 3, bits: 8, compression: "ulaw"), soundData([0x00, 0x80, 0xFF])]))
        #expect(try sound.pcm16() == [-32124, 32124, 0])
    }

    @Test func imaAIFCCountsPackets() throws {
        var packet = [UInt8](repeating: 0, count: 34)
        packet[2] = 0x77
        let sound = try SampledSound(aiff: aifc([common(frames: 1, bits: 16, compression: "ima4"), soundData(packet)]))
        #expect(sound.count == 1 && sound.frameCount == 64)
        #expect(try sound.pcm16().prefix(2) == [11, 41])
    }

    @Test func loopsBetweenMarkers() throws {
        let aiff = file([
            common(frames: 8), markers([(1, 2, "begin"), (2, 6, "end")]), instrument(baseNote: 65, playMode: 1, begin: 1, end: 2),
            soundData([UInt8](repeating: 0, count: 16)),
        ])
        let sound = try SampledSound(aiff: aiff)
        #expect(sound.loop == 2 ..< 6)
        #expect(sound.baseNote == 65)
    }

    @Test func noLoopWithoutPlayModeOrMarkers() throws {
        let samples = soundData([UInt8](repeating: 0, count: 16))
        let marks = markers([(1, 2, "a"), (2, 6, "b")])
        #expect(try SampledSound(aiff: file([common(frames: 8), marks, instrument(playMode: 0, begin: 1, end: 2), samples])).loop == nil)
        #expect(try SampledSound(aiff: file([common(frames: 8), instrument(playMode: 1, begin: 1, end: 2), samples])).loop == nil)
        #expect(try SampledSound(aiff: file([common(frames: 8), marks, instrument(playMode: 1, begin: 1, end: 9), samples])).loop == nil)
        // An end before the start is no loop.
        #expect(try SampledSound(aiff: file([common(frames: 8), marks, instrument(playMode: 1, begin: 2, end: 1), samples])).loop == nil)
    }

    @Test func oddChunksArePaddedAndUnknownOnesSkipped() throws {
        let aiff = file([
            chunk("ANNO", [0x61, 0x62, 0x63]),       // odd: a pad byte follows
            common(frames: 2), chunk("FVER", [0xA2, 0x80, 0x51, 0x40]),
            chunk("NAME", Array("a name!".utf8)),
            soundData([0, 1, 0, 2]),
        ])
        #expect(try SampledSound(aiff: aiff).pcm16() == [1, 2])
    }

    @Test func theSoundDataChunkMayStartPastItsOffset() throws {
        // An offset of 4 skips four bytes of padding before the first sample.
        let sound = try SampledSound(aiff: file([common(frames: 2), soundData([0, 1, 0, 2], offset: 4, padding: 4)]))
        #expect(try sound.pcm16() == [1, 2])
    }

    @Test func samplesAreASliceOfTheFile() throws {
        let aiff = Data(file([common(frames: 2), soundData([0, 1, 0, 2])]))
        let sound = try SampledSound(aiff: aiff)
        #expect(sound.data.startIndex > 0)
        #expect(Array(sound.data) == [0, 1, 0, 2])
    }

    @Test func filesFromAnyBytes() throws {
        let bytes = file([common(frames: 1), soundData([0, 9])])
        #expect(try SampledSound(aiff: Data(bytes)).pcm16() == [9])
        #expect(try SampledSound(aiff: Data([1, 2, 3, 4, 5] + bytes)[5...]).pcm16() == [9])
        #expect(try bytes.withUnsafeBytes { try SampledSound(aiff: $0) }.pcm16() == [9])
    }

    // MARK: Failures

    @Test func notAnAIFFFile() {
        #expect(throws: MacError.badFileFormat) { try SampledSound(aiff: [UInt8]()) }
        #expect(throws: MacError.badFileFormat) { try SampledSound(aiff: Array("RIFFxxxxWAVEfmt ".utf8)) }
        var wrongForm = file([common(frames: 1), soundData([0, 0])])
        wrongForm[8] = 0x58
        #expect(throws: MacError.badFileFormat) { try SampledSound(aiff: wrongForm) }
    }

    @Test func missingChunks() {
        #expect(throws: MacError.badFileFormat) { try SampledSound(aiff: file([soundData([0, 0])])) }
        #expect(throws: MacError.badFileFormat) { try SampledSound(aiff: file([common(frames: 1)])) }
        #expect(throws: MacError.badFileFormat) { try SampledSound(aiff: file([])) }
    }

    @Test func unknownCompressionAndBadChannels() {
        #expect(throws: MacError.badFileFormat) {
            try SampledSound(aiff: aifc([common(frames: 1, compression: "fl32"), soundData([0, 0])]))
        }
        #expect(throws: MacError.badFileFormat) { try SampledSound(aiff: file([common(channels: 0, frames: 1), soundData([0, 0])])) }
        #expect(throws: MacError.badFileFormat) { try SampledSound(aiff: file([common(channels: 1000, frames: 1), soundData([0, 0])])) }
    }

    @Test func chunksPastTheEnd() {
        var aiff = file([common(frames: 1), soundData([0, 0])])
        aiff.removeLast(3)
        #expect(throws: MacError.badFileFormat) { try SampledSound(aiff: aiff) }
    }

    @Test func truncatedFilesNeverTrap() {
        let files = [
            file([common(frames: 4), markers([(1, 0, "a"), (2, 3, "bb")]), instrument(playMode: 1, begin: 1, end: 2), soundData([1, 2, 3, 4, 5, 6, 7, 8])]),
            aifc([common(frames: 1, compression: "ulaw"), soundData([1, 2])]),
        ]
        for aiff in files {
            for length in 0 ... aiff.count {
                if let sound = try? SampledSound(aiff: aiff.prefix(length)) { _ = try? sound.pcm16() }
            }
        }
    }

    @Test func damagedBytesNeverTrap() {
        var generator = QuickDrawRandom(seed: 11)
        let original = file([common(frames: 4), markers([(1, 0, "a"), (2, 3, "bb")]), instrument(playMode: 1, begin: 1, end: 2), soundData([1, 2, 3, 4, 5, 6, 7, 8])])
        for _ in 0 ..< 400 {
            var bytes = original
            for _ in 0 ..< 4 { bytes[Int(UInt16(bitPattern: generator.next())) % bytes.count] = UInt8(truncatingIfNeeded: generator.next()) }
            if let sound = try? SampledSound(aiff: bytes) { _ = try? sound.pcm16() }
        }
    }
}
