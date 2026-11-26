import Testing
import GraphiteBase
import GraphiteSound

@Suite struct ChannelTests {

    let mixer = SoundMixer(sampleRate: 8000)

    private func sound(_ samples: [Int16], rate: Double = 8000) -> SampledSound {
        var bytes: [UInt8] = []
        for sample in samples {
            bytes.append(UInt8(truncatingIfNeeded: sample >> 8))
            bytes.append(UInt8(truncatingIfNeeded: sample))
        }
        return SampledSound(encoding: .signedBigEndian, sampleRate: rate, channels: 1, bitsPerSample: 16, count: samples.count, data: bytes)
    }

    private func render(_ frames: Int, _ mixer: SoundMixer? = nil) -> (left: [Float], right: [Float]) {
        let out = (mixer ?? self.mixer).render(frames: frames)
        return (stride(from: 0, to: out.count, by: 2).map { out[$0] * 32768 }, stride(from: 1, to: out.count, by: 2).map { out[$0] * 32768 })
    }

    private func floats(_ values: [Int]) -> [Float] { values.map(Float.init) }

    // MARK: The queue

    @Test func commandsRunInOrderAndASoundHoldsTheQueue() throws {
        let channel = try mixer.newChannel()
        try channel.doCommand(.buffer(sound([1, 2, 3])))
        try channel.doCommand(.buffer(sound([4, 5])))
        try channel.doCommand(.buffer(sound([6])))
        #expect(channel.status.queuedCommands == 3)
        #expect(render(8).left == floats([1, 2, 3, 4, 5, 6, 0, 0]))
        #expect(channel.status.queuedCommands == 0)
    }

    @Test func settingsRunWhenTheyAreReached() throws {
        let channel = try mixer.newChannel()
        try channel.doCommand(.buffer(sound([1000, 1000])))
        try channel.doCommand(.amplitude(128))
        try channel.doCommand(.buffer(sound([1000, 1000])))
        // The amplitude is for the second sound, not the first.
        #expect(render(4).left == floats([1000, 1000, 500, 500]))
    }

    @Test func aWaitIsSilenceOfItsTime() throws {
        let channel = try mixer.newChannel()
        // Two half-milliseconds is a millisecond: 8 frames at 8000.
        try channel.doCommand(.wait(halfMilliseconds: 2))
        try channel.doCommand(.buffer(sound([7, 8, 9])))
        let out = render(14).left
        #expect(out == floats([0, 0, 0, 0, 0, 0, 0, 0, 7, 8, 9, 0, 0, 0]))
    }

    @Test func waitsAreExactAcrossRenders() throws {
        let channel = try mixer.newChannel()
        try channel.doCommand(.wait(halfMilliseconds: 40))   // 160 frames
        try channel.doCommand(.buffer(sound([5])))
        var all: [Float] = []
        for _ in 0 ..< 8 { all += render(25).left }
        #expect(all.firstIndex { $0 != 0 } == 160)
    }

    @Test func aWaitOfNothingIsNothing() throws {
        let channel = try mixer.newChannel()
        try channel.doCommand(.wait(halfMilliseconds: 0))
        try channel.doCommand(.wait(halfMilliseconds: -4))
        try channel.doCommand(.buffer(sound([3])))
        #expect(render(2).left == floats([3, 0]))
    }

    @Test func callBacksComeWhenReachedWithTheChannelAndCommand() throws {
        let log = Log()
        let channel = try mixer.newChannel { channel, command in log.record(channel, command) }
        try channel.doCommand(.buffer(sound([1, 2, 3])))
        try channel.doCommand(.callBack(param1: 7, param2: 99))
        try channel.doCommand(.buffer(sound([4])))
        _ = render(2)
        #expect(log.commands.isEmpty)
        #expect(render(3).left == floats([3, 4, 0]))
        #expect(log.commands == [.callBack(param1: 7, param2: 99)])
        #expect(log.channels.first === channel)
        _ = render(10)
        #expect(log.commands.count == 1)
    }

    @Test func anImmediateCallBackIsCalledAtOnce() throws {
        let log = Log()
        let channel = try mixer.newChannel { channel, command in log.record(channel, command) }
        try channel.doImmediate(.callBack(param1: 1, param2: 2))
        #expect(log.commands == [.callBack(param1: 1, param2: 2)])
    }

    @Test func aCallBackCanUseTheChannel() throws {
        // It's called after the mixer is let go, so it can send commands.
        let next = sound([9, 9])
        let channel = try mixer.newChannel { channel, _ in try? channel.doCommand(.buffer(next)) }
        try channel.doCommand(.buffer(sound([1])))
        try channel.doCommand(.callBack(param1: 0, param2: 0))
        #expect(render(2).left == floats([1, 0]))
        #expect(render(3).left == floats([9, 9, 0]))
    }

    // MARK: Flush, quiet and the two pauses

    @Test func flushEmptiesTheQueue() throws {
        let channel = try mixer.newChannel()
        try channel.doCommand(.buffer(sound([1, 2])))
        try channel.doCommand(.buffer(sound([3, 4])))
        try channel.doImmediate(.flush)
        #expect(channel.status.queuedCommands == 0)
        #expect(render(4).left == floats([0, 0, 0, 0]))
        try channel.doCommand(.buffer(sound([5])))
        try channel.doCommand(.flush)
        #expect(render(2).left == floats([5, 0]))
    }

    @Test func quietStopsTheSoundAndTheQueueGoesOn() throws {
        let channel = try mixer.newChannel()
        try channel.doCommand(.buffer(sound([1, 2, 3, 4, 5, 6])))
        try channel.doCommand(.buffer(sound([7, 8])))
        #expect(render(2).left == floats([1, 2]))
        try channel.doImmediate(.quiet)
        #expect(render(3).left == floats([7, 8, 0]))
    }

    @Test func pauseHoldsTheQueueNotTheSound() throws {
        let channel = try mixer.newChannel()
        try channel.doCommand(.buffer(sound([1, 2, 3])))
        try channel.doCommand(.pause)
        try channel.doCommand(.buffer(sound([4, 5])))
        #expect(render(6).left == floats([1, 2, 3, 0, 0, 0]))
        #expect(channel.status.isPaused)
        #expect(channel.status.queuedCommands == 1)
        try channel.doImmediate(.resume)
        #expect(!channel.status.isPaused)
        #expect(render(3).left == floats([4, 5, 0]))
    }

    @Test func aQueuedResumeCantRunWhilePaused() throws {
        let channel = try mixer.newChannel()
        try channel.doImmediate(.pause)
        try channel.doCommand(.resume)
        try channel.doCommand(.buffer(sound([1])))
        #expect(render(2).left == floats([0, 0]))
        try channel.doImmediate(.resume)
        #expect(render(2).left == floats([1, 0]))
    }

    @Test func pausingPlaybackHoldsTheSoundWhereItIs() throws {
        let channel = try mixer.newChannel()
        try channel.play(sound([1, 2, 3, 4, 5]))
        #expect(render(2).left == floats([1, 2]))
        try channel.doImmediate(.pausePlayback)
        #expect(channel.status.isPaused && channel.status.isBusy)
        #expect(render(100).left == [Float](repeating: 0, count: 100))
        try channel.doImmediate(.resumePlayback)
        #expect(!channel.status.isPaused)
        #expect(render(4).left == floats([3, 4, 5, 0]))
    }

    // MARK: Sync

    @Test func channelsAtASyncGoOnTogether() throws {
        let one = try mixer.newChannel(), two = try mixer.newChannel()
        try one.doImmediate(.volume(left: 256, right: 0))
        try two.doImmediate(.volume(left: 0, right: 256))
        try one.doCommand(.wait(halfMilliseconds: 40))      // 160 frames
        try one.doCommand(.sync(count: 2, identifier: 7))
        try one.doCommand(.buffer(sound([1000, 1000, 1000, 1000])))
        try two.doCommand(.sync(count: 2, identifier: 7))
        try two.doCommand(.buffer(sound([2000, 2000, 2000, 2000])))
        let out = render(400)
        // The first reaches the sync in the slice of frames 128 to 191, so both
        // go on at 192, the start of the next.
        #expect(out.left.firstIndex { $0 != 0 } == 192)
        #expect(out.right.firstIndex { $0 != 0 } == 192)
        #expect(Array(out.left[192 ..< 197]) == floats([1000, 1000, 1000, 1000, 0]))
        #expect(Array(out.right[192 ..< 197]) == floats([2000, 2000, 2000, 2000, 0]))
        #expect(out.left.filter { $0 != 0 }.count == 4 && out.right.filter { $0 != 0 }.count == 4)
    }

    @Test func aSyncWaitsForEveryChannelItNames() throws {
        let one = try mixer.newChannel(), two = try mixer.newChannel()
        for channel in [one, two] {
            try channel.doCommand(.sync(count: 3, identifier: 1))
            try channel.doCommand(.buffer(sound([5])))
        }
        #expect(render(300).left == [Float](repeating: 0, count: 300))
        #expect(one.status.isBusy && two.status.isBusy)
        // A third channel completes it, and all three go on.
        let three = try mixer.newChannel()
        try three.doCommand(.sync(count: 3, identifier: 1))
        try three.doCommand(.buffer(sound([5])))
        let out = render(128).left
        #expect(out.firstIndex { $0 != 0 } == 64)
        #expect(out[64] == 15)
    }

    @Test func syncsOfOtherIdentifiersAreSeparate() throws {
        let one = try mixer.newChannel(), two = try mixer.newChannel()
        try one.doCommand(.sync(count: 2, identifier: 1))
        try one.doCommand(.buffer(sound([5])))
        try two.doCommand(.sync(count: 2, identifier: 2))
        try two.doCommand(.buffer(sound([5])))
        #expect(render(200).left == [Float](repeating: 0, count: 200))
    }

    @Test func aSyncOfOneIsNothing() throws {
        let channel = try mixer.newChannel()
        try channel.doCommand(.sync(count: 1, identifier: 3))
        try channel.doCommand(.sync(count: 0, identifier: 3))
        try channel.doCommand(.buffer(sound([4])))
        #expect(render(2).left == floats([4, 0]))
    }

    @Test func aDisposedChannelLeavesItsSync() throws {
        let one = try mixer.newChannel(), two = try mixer.newChannel()
        try one.doCommand(.sync(count: 2, identifier: 1))
        _ = render(10)
        one.dispose()
        try two.doCommand(.sync(count: 2, identifier: 1))
        try two.doCommand(.buffer(sound([5])))
        // The one that left doesn't count.
        #expect(render(200).left == [Float](repeating: 0, count: 200))
    }

    // MARK: Status and disposal

    @Test func statusFollowsTheChannel() throws {
        let channel = try mixer.newChannel()
        #expect(channel.status == ChannelStatus(isBusy: false, isPaused: false, queuedCommands: 0))
        try channel.play(sound([1, 2, 3]))
        #expect(channel.status.isBusy)
        _ = render(2)
        #expect(channel.status.isBusy)
        _ = render(2)
        #expect(!channel.status.isBusy)
        try channel.doCommand(.wait(halfMilliseconds: 2000))
        #expect(channel.status.isBusy)
    }

    @Test func disposingStopsItAtOnce() throws {
        let channel = try mixer.newChannel()
        try channel.play(sound([1, 2, 3, 4]))
        try channel.doCommand(.buffer(sound([5])))
        channel.dispose()
        #expect(mixer.channelCount == 0)
        #expect(render(6).left == [Float](repeating: 0, count: 6))
        #expect(throws: MacError.badChannel) { try channel.doImmediate(.quiet) }
        #expect(throws: MacError.badChannel) { try channel.doCommand(.null) }
        #expect(throws: MacError.badChannel) { try channel.play(sound([1])) }
        #expect(!channel.status.isBusy)
        channel.dispose()
    }

    @Test func disposingNotQuietPlaysWhatIsThere() throws {
        let channel = try mixer.newChannel()
        try channel.doCommand(.buffer(sound([1, 2, 3])))
        try channel.doCommand(.buffer(sound([4])))
        channel.dispose(quietNow: false)
        #expect(mixer.channelCount == 1)
        #expect(render(6).left == floats([1, 2, 3, 4, 0, 0]))
        #expect(mixer.channelCount == 0)
        #expect(throws: MacError.badChannel) { try channel.doCommand(.null) }
    }

    @Test func disposingAnIdleChannelIsAtOnce() throws {
        let channel = try mixer.newChannel()
        channel.dispose(quietNow: false)
        #expect(mixer.channelCount == 0)
    }

    // MARK: Errors

    @Test func theQueueHoldsAHundredAndTwentyEight() throws {
        let channel = try mixer.newChannel()
        try channel.doImmediate(.pause)
        for _ in 0 ..< 128 { try channel.doCommand(.null) }
        #expect(throws: MacError.queueFull) { try channel.doCommand(.null) }
        #expect(channel.status.queuedCommands == 128)
        try channel.doImmediate(.flush)
        try channel.doCommand(.null)
    }

    @Test func soundsThatCantBePlayedAreRefused() throws {
        let channel = try mixer.newChannel()
        let mace = SampledSound(encoding: .mace3, sampleRate: 8000, channels: 1, bitsPerSample: 16, count: 1, data: [1, 2])
        let noChannels = SampledSound(encoding: .signedBigEndian, sampleRate: 8000, channels: 0, bitsPerSample: 16, count: 1, data: [1, 2])
        #expect(throws: MacError.unimplemented) { try channel.doCommand(.buffer(mace)) }
        #expect(throws: MacError.unimplemented) { try channel.doImmediate(.buffer(mace)) }
        #expect(throws: MacError.unimplemented) { try channel.play(mace) }
        #expect(throws: MacError.badFormat) { try channel.doCommand(.buffer(noChannels)) }
        #expect(channel.status.queuedCommands == 0)
    }

    @Test func onlySampledSynthsAreChannels() {
        #expect(throws: MacError.unimplemented) { try mixer.newChannel(synth: .squareWave) }
        #expect(throws: MacError.unimplemented) { try mixer.newChannel(synth: .waveTable) }
        #expect(mixer.channelCount == 0)
    }

    @Test func channelsAreCounted() throws {
        let a = try mixer.newChannel(), b = try mixer.newChannel()
        #expect(mixer.channelCount == 2)
        a.dispose()
        #expect(mixer.channelCount == 1)
        withExtendedLifetime(b) {}
    }

    @Test func aSoundWithADecodedFormatPlays() throws {
        // µ-law bytes, decoded when the command is given.
        let ulaw = SampledSound(encoding: .ulaw, sampleRate: 8000, channels: 1, bitsPerSample: 16, count: 2, data: [0x80, 0x00])
        let channel = try mixer.newChannel()
        try channel.play(ulaw)
        #expect(render(3).left == floats([32124, -32124, 0]))
    }
}

/// What a callback was given.
final class Log: @unchecked Sendable {
    private(set) var commands: [SoundCommand] = []
    private(set) var channels: [SoundChannel] = []
    func record(_ channel: SoundChannel, _ command: SoundCommand) {
        channels.append(channel)
        commands.append(command)
    }
}
