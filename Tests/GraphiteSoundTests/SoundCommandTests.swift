import Foundation
import Testing
import GraphiteBase
import GraphiteSound

@Suite struct SoundCommandTests {

    // MARK: Command words

    @Test func commandsThatCarryNoSound() {
        #expect(SoundCommand(code: 0, param1: 0, param2: 0) == .null)
        #expect(SoundCommand(code: 3, param1: 0, param2: 0) == .quiet)
        #expect(SoundCommand(code: 4, param1: 0, param2: 0) == .flush)
        #expect(SoundCommand(code: 5, param1: 0, param2: 0x0004) == .reInit(.noInterpolation))
        #expect(SoundCommand(code: 10, param1: 40, param2: 0) == .wait(halfMilliseconds: 40))
        #expect(SoundCommand(code: 11, param1: 0, param2: 0) == .pause)
        #expect(SoundCommand(code: 12, param1: 0, param2: 0) == .resume)
        #expect(SoundCommand(code: 13, param1: 5, param2: 6) == .callBack(param1: 5, param2: 6))
        #expect(SoundCommand(code: 14, param1: 2, param2: 77) == .sync(count: 2, identifier: 77))
        #expect(SoundCommand(code: 42, param1: 0, param2: 67) == .frequency(note: 67))
        #expect(SoundCommand(code: 43, param1: 128, param2: 0) == .amplitude(128))
        #expect(SoundCommand(code: 82, param1: 0, param2: 0x1_0000) == .rate(0x1_0000))
        #expect(SoundCommand(code: 86, param1: 0, param2: 0x2_0000) == .rateMultiplier(0x2_0000))
    }

    @Test func theVolumeCommandsWordsAreLeftThenRight() {
        // The low word is the left volume, the high word the right.
        #expect(SoundCommand(code: 46, param1: 0, param2: Int32(bitPattern: 0x0040_0100)) == .volume(left: 0x0100, right: 0x0040))
        #expect(SoundCommand(code: 46, param1: 0, param2: Int32(bitPattern: 0xFFFF_0000)) == .volume(left: 0, right: 0xFFFF))
    }

    @Test func theHighBitOnlySaysThereIsSoundData() {
        #expect(SoundCommand(code: 0x8003, param1: 0, param2: 0) == .quiet)
        #expect(SoundCommand(code: 0x800D, param1: 1, param2: 2) == .callBack(param1: 1, param2: 2))
    }

    @Test func commandsThatAreSoundsOrUnknownAreNil() {
        // soundCmd and bufferCmd point at a sound, with or without the high bit.
        for code: UInt16 in [80, 81, 0x8050, 0x8051] { #expect(SoundCommand(code: code, param1: 0, param2: 20) == nil, "\(code)") }
        // Synthesizer commands, and numbers that are no command.
        for code: UInt16 in [1, 2, 24, 25, 40, 41, 44, 45, 47, 60, 61, 83, 84, 85, 87, 90, 91, 200, 0x7001] {
            #expect(SoundCommand(code: code, param1: 0, param2: 0) == nil, "\(code)")
        }
    }

    @Test func initBits() {
        #expect(SoundInit.noInterpolation.rawValue == 0x0004)
        #expect(SoundInit.noDrop.rawValue == 0x0008)
        #expect(SoundInit.mono.rawValue == 0x0080)
        #expect(SoundInit.stereo.rawValue == 0x00C0)
        #expect(SoundInit.mace3.rawValue == 0x0300)
        #expect(SoundInit.mace6.rawValue == 0x0400)
        #expect(SoundInit([.stereo, .noInterpolation]).contains(.noInterpolation))
        #expect(SoundSynth.sampled.rawValue == 5 && SoundSynth.squareWave.rawValue == 1 && SoundSynth.waveTable.rawValue == 3)
    }

    @Test func versionIsThreePointNine() {
        let version = SoundMixer.version
        #expect(version.major == 3 && version.minorAndBugFix == 0x09 && version.stage == 0x80 && version.nonRelease == 0)
    }

    // MARK: A device

    final class Device: AudioOutput, @unchecked Sendable {
        let sampleRate: Int
        private(set) var render: (@Sendable (UnsafeMutableBufferPointer<Float>) -> Void)?
        private(set) var starts = 0
        private(set) var stops = 0
        init(sampleRate: Int) { self.sampleRate = sampleRate }
        func start(render: @escaping @Sendable (UnsafeMutableBufferPointer<Float>) -> Void) {
            starts += 1
            self.render = render
        }
        func stop() {
            stops += 1
            render = nil
        }
    }

    @Test func aMixerPlaysThroughADevice() throws {
        let device = Device(sampleRate: 22050)
        let mixer = SoundMixer(output: device)
        #expect(mixer.sampleRate == 22050)
        #expect(device.starts == 1)
        let sound = SampledSound(encoding: .signedBigEndian, sampleRate: 22050, channels: 1, bitsPerSample: 16, count: 2, data: [0x03, 0xE8, 0xFC, 0x18])
        let channel = try mixer.newChannel()
        try channel.play(sound)
        var buffer = [Float](repeating: 9, count: 8)
        buffer.withUnsafeMutableBufferPointer { device.render?($0) }
        #expect(buffer == [1000, 1000, -1000, -1000, 0, 0, 0, 0].map { Float($0) / 32768 })
        mixer.stop()
        #expect(device.stops == 1 && device.render == nil)
        mixer.stop()
        #expect(device.stops == 1)
    }

    @Test func aBufferOfAnOddCountHasNoHalfFrame() {
        let mixer = SoundMixer(sampleRate: 8000)
        var buffer = [Float](repeating: 5, count: 5)
        buffer.withUnsafeMutableBufferPointer { mixer.render(into: $0) }
        #expect(Array(buffer.prefix(4)) == [0, 0, 0, 0])
        #expect(buffer[4] == 5)
    }

    // MARK: Threads

    @Test func commandsFromOtherThreadsWhileRendering() async throws {
        let mixer = SoundMixer(sampleRate: 8000)
        var bytes: [UInt8] = []
        for sample in 0 ..< 800 { bytes += [UInt8(sample >> 8 & 0x7F), UInt8(sample & 0xFF)] }
        let sound = SampledSound(encoding: .signedBigEndian, sampleRate: 8000, channels: 1, bitsPerSample: 16, count: 800, data: bytes)
        let played = Counter()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for _ in 0 ..< 300 { _ = mixer.render(frames: 100) }
            }
            for worker in 0 ..< 4 {
                group.addTask {
                    for round in 0 ..< 50 {
                        guard let channel = try? mixer.newChannel() else { continue }
                        try? channel.play(sound) { played.increment() }
                        try? channel.doCommand(.amplitude(worker * 40 + round))
                        try? channel.doCommand(.wait(halfMilliseconds: 10))
                        try? channel.doCommand(.sync(count: 2, identifier: Int32(round % 3)))
                        _ = channel.status
                        if round % 4 == 0 { channel.dispose() }
                    }
                }
            }
        }
        // Whatever the channels were doing, rendering goes on and ends.
        for _ in 0 ..< 200 { _ = mixer.render(frames: 100) }
        #expect(played.value <= 200)
    }
}
