import Testing
import GraphiteBase
import GraphiteSound

@Suite struct MixerTests {

    let mixer = SoundMixer(sampleRate: 8000)

    /// 16-bit mono (or interleaved) samples as a sound.
    private func sound(_ samples: [Int16], rate: Double = 8000, channels: Int = 1, baseNote: Int = 60, loop: Range<Int>? = nil) -> SampledSound {
        var bytes: [UInt8] = []
        for sample in samples {
            bytes.append(UInt8(truncatingIfNeeded: sample >> 8))
            bytes.append(UInt8(truncatingIfNeeded: sample))
        }
        return SampledSound(encoding: .signedBigEndian, sampleRate: rate, channels: channels, bitsPerSample: 16,
                            count: samples.count / channels, data: bytes, baseNote: baseNote, loop: loop)
    }

    /// The left and right of rendered frames, as the 16-bit values they came from.
    private func render(_ frames: Int, _ mixer: SoundMixer? = nil) -> (left: [Float], right: [Float]) {
        let out = (mixer ?? self.mixer).render(frames: frames)
        return (stride(from: 0, to: out.count, by: 2).map { out[$0] * 32768 }, stride(from: 1, to: out.count, by: 2).map { out[$0] * 32768 })
    }

    private func floats(_ values: [Int]) -> [Float] { values.map(Float.init) }

    // MARK: Playing

    @Test func aMonoSoundPlaysToBothSides() throws {
        let channel = try mixer.newChannel()
        try channel.play(sound([100, -200, 300, 400]))
        let out = render(6)
        #expect(out.left == floats([100, -200, 300, 400, 0, 0]))
        #expect(out.right == out.left)
    }

    @Test func aStereoSoundKeepsItsSides() throws {
        let channel = try mixer.newChannel()
        try channel.play(sound([1, -1, 2, -2, 3, -3], channels: 2))
        let out = render(4)
        #expect(out.left == floats([1, 2, 3, 0]))
        #expect(out.right == floats([-1, -2, -3, 0]))
    }

    @Test func silenceWithNothingPlaying() {
        #expect(render(100).left == [Float](repeating: 0, count: 100))
        #expect(mixer.render(frames: 0).isEmpty)
        #expect(mixer.render(frames: -5).isEmpty)
    }

    @Test func rendersContinueWhereTheLastLeftOff() throws {
        let samples = (0 ..< 300).map { Int16($0 * 10) }
        try mixer.newChannel().play(sound(samples))
        var all: [Float] = []
        for count in [1, 63, 64, 65, 200, 7] { all += render(count).left }
        #expect(all.count == 400)
        #expect(Array(all.prefix(300)) == floats(samples.map(Int.init)))
        #expect(all.suffix(100).allSatisfy { $0 == 0 })
    }

    @Test func channelsAreAddedAndClipped() throws {
        let a = try mixer.newChannel(), b = try mixer.newChannel()
        try a.play(sound([100, 20000]))
        try b.play(sound([200, 20000]))
        let out = render(3)
        #expect(out.left == [300, 32768, 0])
    }

    @Test func anotherSoundTakesTheChannelOver() throws {
        let channel = try mixer.newChannel()
        try channel.play(sound([1, 2, 3, 4, 5, 6]))
        _ = render(2)
        try channel.doImmediate(.buffer(sound([9, 8])))
        #expect(render(3).left == floats([9, 8, 0]))
    }

    // MARK: Resampling

    @Test func aSlowerSoundIsInterpolated() throws {
        try mixer.newChannel().play(sound([0, 1000], rate: 4000))
        #expect(render(5).left == floats([0, 500, 1000, 1000, 0]))
    }

    @Test func withoutInterpolationSamplesRepeat() throws {
        try mixer.newChannel(initBits: .noInterpolation).play(sound([0, 1000], rate: 4000))
        #expect(render(5).left == floats([0, 0, 1000, 1000, 0]))
    }

    @Test func reInitChangesInterpolation() throws {
        let channel = try mixer.newChannel()
        try channel.doImmediate(.reInit(.noInterpolation))
        try channel.play(sound([0, 1000], rate: 4000))
        #expect(render(4).left == floats([0, 0, 1000, 1000]))
    }

    @Test func aFasterSoundSkipsSamples() throws {
        try mixer.newChannel().play(sound([10, 20, 30, 40, 50, 60], rate: 16000))
        #expect(render(4).left == floats([10, 30, 50, 0]))
    }

    @Test func aNoteAnOctaveUpPlaysTwiceAsFast() throws {
        let channel = try mixer.newChannel()
        try channel.play(sound([10, 20, 30, 40, 50, 60]))
        try channel.doImmediate(.frequency(note: 72))
        let out = render(4).left
        for (got, wanted) in zip(out, floats([10, 30, 50, 0])) { #expect(abs(got - wanted) < 0.01) }
    }

    @Test func theBaseNoteIsTheNoteItPlaysAsRecorded() throws {
        let channel = try mixer.newChannel()
        try channel.play(sound([10, 20, 30, 40], baseNote: 72))
        try channel.doImmediate(.frequency(note: 72))
        #expect(render(5).left == floats([10, 20, 30, 40, 0]))
    }

    @Test func rateMultipliesThePitch() throws {
        for command in [SoundCommand.rate(0x2_0000), .rateMultiplier(0x2_0000)] {
            let mixer = SoundMixer(sampleRate: 8000)
            let channel = try mixer.newChannel()
            try channel.play(sound([10, 20, 30, 40, 50, 60]))
            try channel.doImmediate(command)
            #expect(render(4, mixer).left == floats([10, 30, 50, 0]))
        }
    }

    // MARK: Volume and pan

    @Test func panAndVolume() throws {
        func play(_ command: SoundCommand) throws -> (left: [Float], right: [Float]) {
            let mixer = SoundMixer(sampleRate: 8000)
            let channel = try mixer.newChannel()
            try channel.play(sound([1000, 1000]))
            try channel.doImmediate(command)
            return render(2, mixer)
        }
        let left = try play(.volume(left: 256, right: 0))
        #expect(left.left == floats([1000, 1000]) && left.right == floats([0, 0]))
        let right = try play(.volume(left: 0, right: 256))
        #expect(right.left == floats([0, 0]) && right.right == floats([1000, 1000]))
        let half = try play(.volume(left: 128, right: 128))
        #expect(half.left == floats([500, 500]) && half.right == half.left)
        // The louder side sets the amplitude and the pan moves toward it.
        let mostlyLeft = try play(.volume(left: 256, right: 64))
        #expect(mostlyLeft.left == floats([1000, 1000]))
        #expect(mostlyLeft.right == floats([400, 400]))
        let silent = try play(.volume(left: 0, right: 0))
        #expect(silent.left == floats([0, 0]) && silent.right == silent.left)
    }

    @Test func amplitude() throws {
        func play(_ amplitude: Int) throws -> [Float] {
            let mixer = SoundMixer(sampleRate: 8000)
            let channel = try mixer.newChannel()
            try channel.play(sound([1000]))
            try channel.doImmediate(.amplitude(amplitude))
            return render(1, mixer).left
        }
        #expect(try play(256) == [1000])
        #expect(try play(128) == [500])
        #expect(try play(0) == [0])
        #expect(try play(-5) == [0])
        // Capped at 2.5 times as recorded.
        #expect(try play(100_000) == [2500])
    }

    @Test func theOutputVolume() throws {
        try mixer.newChannel().play(sound([1000, 1000]))
        mixer.outputVolume = (0.5, 0)
        let out = render(2)
        #expect(out.left == floats([500, 500]) && out.right == floats([0, 0]))
        mixer.outputVolume = (-1, -1)
        #expect(mixer.outputVolume.left == 0 && mixer.outputVolume.right == 0)
    }

    @Test func theDefaultOutputVolumeIsAWordASide() {
        #expect(mixer.defaultOutputVolume == 0x0100_0100)
        mixer.defaultOutputVolume = 0x0100_0080
        #expect(mixer.outputVolume.left == 0.5 && mixer.outputVolume.right == 1)
        #expect(mixer.defaultOutputVolume == 0x0100_0080)
        mixer.defaultOutputVolume = 0xFFFF_FFFF
        #expect(mixer.defaultOutputVolume == 0xFFFF_FFFF)
    }

    // MARK: Loops and the end

    @Test func aHeaderLoopRepeats() throws {
        let channel = try mixer.newChannel()
        try channel.play(sound([1, 2, 3, 4, 5, 6].map { $0 * 1000 }, loop: 2 ..< 5))
        #expect(withExtendedLifetime(channel) { render(10).left } == floats([1, 2, 3, 4, 5, 3, 4, 5, 3, 4].map { $0 * 1000 }))
    }

    @Test func loopCanBeStoppedAndForced() throws {
        let samples = [1, 2, 3, 4, 5, 6].map { Int16($0 * 1000) }
        let stopped = SoundMixer(sampleRate: 8000)
        let channel = try stopped.newChannel()
        try channel.play(sound(samples, loop: 2 ..< 5))
        try channel.doImmediate(.loop(false))
        #expect(render(8, stopped).left == floats([1, 2, 3, 4, 5, 6, 0, 0].map { $0 * 1000 }))

        let forced = SoundMixer(sampleRate: 8000)
        let other = try forced.newChannel()
        try other.play(sound(samples))
        try other.doImmediate(.loop(true))
        #expect(render(8, forced).left == floats([1, 2, 3, 4, 5, 6, 1, 2].map { $0 * 1000 }))
    }

    @Test func aLoopTooShortOrPastTheEndIsNoLoop() throws {
        let samples = [1, 2, 3, 4].map { Int16($0 * 1000) }
        let one = SoundMixer(sampleRate: 8000)
        let first = try one.newChannel()
        try first.play(sound(samples, loop: 1 ..< 2))
        #expect(withExtendedLifetime(first) { render(6, one).left } == floats([1, 2, 3, 4, 0, 0].map { $0 * 1000 }))
        // One past the end stops at the end.
        let past = SoundMixer(sampleRate: 8000)
        let second = try past.newChannel()
        try second.play(sound(samples, loop: 2 ..< 40))
        #expect(withExtendedLifetime(second) { render(8, past).left } == floats([1, 2, 3, 4, 3, 4, 3, 4].map { $0 * 1000 }))
    }

    @Test func aLoopWorksAtOtherRates() throws {
        let mixer = SoundMixer(sampleRate: 8000)
        let channel = try mixer.newChannel(initBits: .noInterpolation)
        try channel.play(sound([10, 20, 30, 40], rate: 4000, loop: 2 ..< 4))
        // Each frame twice, then the loop's two frames, twice each.
        #expect(withExtendedLifetime(channel) { render(12, mixer).left } == floats([10, 10, 20, 20, 30, 30, 40, 40, 30, 30, 40, 40]))
    }

    @Test func aChannelLetGoOfPlaysItsSoundOutAndGoes() throws {
        // Nothing holds the channel, which is no reason to cut the sound off.
        try mixer.newChannel().play(sound([1, 2, 3, 4]))
        #expect(mixer.channelCount == 1)
        #expect(render(6).left == floats([1, 2, 3, 4, 0, 0]))
        #expect(mixer.channelCount == 0)
    }

    @Test func aChannelLetGoOfPlaysALoopOnce() throws {
        try mixer.newChannel().play(sound([1, 2, 3, 4, 5, 6].map { $0 * 1000 }, loop: 2 ..< 5))
        #expect(render(8).left == floats([1, 2, 3, 4, 5, 6, 0, 0].map { $0 * 1000 }))
        #expect(mixer.channelCount == 0)
    }

    @Test func aChannelLetGoOfRunsItsQueueToo() throws {
        do {
            let channel = try mixer.newChannel()
            try channel.doCommand(.buffer(sound([1, 2])))
            try channel.doCommand(.buffer(sound([3, 4])))
        }
        #expect(render(6).left == floats([1, 2, 3, 4, 0, 0]))
        #expect(mixer.channelCount == 0)
    }

    @Test func completionIsCalledOnceAtTheEnd() throws {
        let calls = Counter()
        let channel = try mixer.newChannel()
        try channel.play(sound([1, 2, 3])) { calls.increment() }
        #expect(calls.value == 0)
        _ = render(2)
        #expect(calls.value == 0)
        _ = render(2)
        #expect(calls.value == 1)
        _ = render(100)
        #expect(calls.value == 1)
    }

    @Test func completionIsNotCalledWhenStopped() throws {
        let calls = Counter()
        let channel = try mixer.newChannel()
        try channel.play(sound([1, 2, 3, 4, 5, 6])) { calls.increment() }
        _ = render(2)
        try channel.doImmediate(.quiet)
        _ = render(20)
        #expect(calls.value == 0)
        #expect(!channel.status.isBusy)
    }

    @Test func aSoundWithNoFramesCompletesAtOnce() throws {
        let calls = Counter()
        let empty = SampledSound(encoding: .signedBigEndian, sampleRate: 8000, channels: 1, bitsPerSample: 16, count: 0, data: [UInt8]())
        try mixer.newChannel().play(empty) { calls.increment() }
        #expect(calls.value == 1)
        #expect(render(2).left == floats([0, 0]))
    }
}

/// A count a callback can add to.
final class Counter: @unchecked Sendable {
    private(set) var value = 0
    func increment() { value += 1 }
}
