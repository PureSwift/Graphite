// The mixer: channels' sounds resampled to the device's rate, panned,
// amplified and added into stereo float frames.
//
// Adapted from cmixer by rxi (https://github.com/rxi/cmixer) and from Pomme:
//
// Copyright (c) 2017 rxi
// Copyright (c) 2020 Iliyas Jorio
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Synchronization
import GraphiteBase

public final class SoundMixer: Sendable {

    /// The frames a second it renders.
    public let sampleRate: Int

    private let state: Mutex<MixerState>

    /// The frames mixed between a channel's changes of what it is doing, which
    /// is how closely channels that wait for each other start together.
    static let slice = 64

    /// A mixer that renders at a rate, for a program to pull frames from.
    public init(sampleRate: Int = 44100) {
        self.sampleRate = max(1, sampleRate)
        state = Mutex(MixerState())
    }

    /// A mixer that plays through an audio device, at its rate, until `stop`.
    /// The device holds the mixer while it plays.
    public convenience init(output: any AudioOutput) {
        self.init(sampleRate: output.sampleRate)
        state.withLock { $0.output = output }
        output.start { [self] buffer in render(into: buffer) }
    }

    /// Stops the device the mixer plays through.
    public func stop() {
        let output = state.withLock { state in
            defer { state.output = nil }
            return state.output
        }
        output?.stop()
    }

    // MARK: Volume

    /// The output's volume, each side, 1 for as mixed. Its default is 1.
    public var outputVolume: (left: Double, right: Double) {
        get { state.withLock { $0.volume } }
        set { state.withLock { $0.volume = (max(0, newValue.left), max(0, newValue.right)) } }
    }

    /// GetDefaultOutputVolume and SetDefaultOutputVolume: the output's volume
    /// as the Sound Manager says it, the left in the low word and the right in
    /// the high, 256 for full.
    public var defaultOutputVolume: UInt32 {
        get {
            let volume = outputVolume
            let left = UInt32(min(volume.left * 256, 65535)), right = UInt32(min(volume.right * 256, 65535))
            return right << 16 | left
        }
        set {
            outputVolume = (Double(newValue & 0xFFFF) / 256, Double(newValue >> 16) / 256)
        }
    }

    /// SndSoundManagerVersion: 3.0.9, a final release, as a NumVersion.
    public static var version: (major: UInt8, minorAndBugFix: UInt8, stage: UInt8, nonRelease: UInt8) { (3, 0x09, 0x80, 0) }

    // MARK: Channels

    /// SndNewChannel: a channel of a synthesizer. `unimplemented` for any but
    /// sampled sounds.
    public func newChannel(
        synth: SoundSynth = .sampled, initBits: SoundInit = [],
        callBack: (@Sendable (SoundChannel, SoundCommand) -> Void)? = nil
    ) throws(MacError) -> SoundChannel {
        guard synth == .sampled else { throw .unimplemented }
        let channel = ChannelState()
        channel.callBack = callBack
        channel.interpolates = !initBits.contains(.noInterpolation)
        let handle = SoundChannel(mixer: self, state: channel)
        channel.handle = handle
        state.withLock { $0.channels.append(channel) }
        return handle
    }

    /// The channels there are.
    public var channelCount: Int {
        state.withLock { $0.channels.count }
    }

    // MARK: Rendering

    /// The next `frames` frames: stereo, left then right, as floats of -1 to
    /// 1, with the output's volume applied and clipped.
    public func render(frames: Int) -> [Float] {
        var frames = [Float](repeating: 0, count: max(0, frames) * 2)
        frames.withUnsafeMutableBufferPointer { render(into: $0) }
        return frames
    }

    /// Fills a buffer of stereo frames. Callbacks and completions it calls for
    /// are called after the mixer is let go, so they can use its channels.
    public func render(into buffer: UnsafeMutableBufferPointer<Float>) {
        let frames = buffer.count / 2
        var events: [@Sendable () -> Void] = []
        state.withLock { state in
            for index in 0 ..< frames * 2 { buffer[index] = 0 }
            var offset = 0
            while offset < frames {
                let count = min(Self.slice, frames - offset)
                for channel in state.pendingReleases { channel.syncIdentifier = nil }
                state.pendingReleases.removeAll()
                for channel in state.channels {
                    state.advance(channel, frames: count, into: buffer, at: offset, sampleRate: sampleRate, events: &events)
                }
                offset += count
            }
            state.removeRetiredChannels()
            let left = Float(state.volume.left), right = Float(state.volume.right)
            for frame in 0 ..< frames {
                buffer[frame * 2] = min(max(buffer[frame * 2] * left, -1), 1)
                buffer[frame * 2 + 1] = min(max(buffer[frame * 2 + 1] * right, -1), 1)
            }
        }
        for event in events { event() }
    }

    // MARK: Channel operations, from SoundChannel

    func run(_ command: SoundCommand, completion: (@Sendable () -> Void)? = nil, on channel: ChannelState) throws(MacError) {
        let prepared = try Self.prepare(command)
        var events: [@Sendable () -> Void] = []
        try state.withLock { (state: inout MixerState) throws(MacError) in
            guard !channel.isDisposed else { throw MacError.badChannel }
            state.execute(command, prepared: prepared, completion: completion, on: channel, sampleRate: sampleRate, events: &events)
        }
        for event in events { event() }
    }

    func enqueue(_ command: SoundCommand, on channel: ChannelState) throws(MacError) {
        let prepared = try Self.prepare(command)
        try state.withLock { (state: inout MixerState) throws(MacError) in
            guard !channel.isDisposed else { throw MacError.badChannel }
            guard channel.queue.count < ChannelState.queueCapacity else { throw MacError.queueFull }
            channel.queue.append((command, prepared))
        }
    }

    func status(of channel: ChannelState) -> ChannelStatus {
        state.withLock { _ in
            ChannelStatus(
                isBusy: !channel.isDisposed && !channel.isIdle,
                isPaused: channel.isQueuePaused || channel.voice?.isPaused == true,
                queuedCommands: channel.queue.count)
        }
    }

    func dispose(_ channel: ChannelState, quietNow: Bool) {
        state.withLock { state in
            if quietNow || channel.isIdle {
                state.remove(channel)
            } else {
                channel.retiresWhenIdle = true
            }
        }
    }

    /// A sound command's sound decoded and checked, where it has one.
    private static func prepare(_ command: SoundCommand) throws(MacError) -> PreparedSound? {
        if case .buffer(let sound) = command { return try PreparedSound(sound) }
        return nil
    }
}

// MARK: - Running channels

/// The mixer's channels and what they share, used with its lock held.
struct MixerState {

    var channels: [ChannelState] = []

    /// Channels at a sync, by its identifier.
    var syncGroups: [Int32: [ChannelState]] = [:]

    /// Channels whose sync is complete, which go on at the start of the next
    /// slice, all together.
    var pendingReleases: [ChannelState] = []

    var volume: (left: Double, right: Double) = (1, 1)

    var output: (any AudioOutput)?

    mutating func remove(_ channel: ChannelState) {
        channel.isDisposed = true
        channel.voice = nil
        channel.queue.removeAll()
        channel.waitRemaining = nil
        channel.syncIdentifier = nil
        channels.removeAll { $0 === channel }
        for (identifier, group) in syncGroups {
            let rest = group.filter { $0 !== channel }
            syncGroups[identifier] = rest.isEmpty ? nil : rest
        }
        pendingReleases.removeAll { $0 === channel }
    }

    mutating func removeRetiredChannels() {
        for channel in channels where channel.retiresWhenIdle && channel.isIdle { remove(channel) }
    }

    /// Runs one command on a channel: queued commands as they are reached,
    /// immediate ones at once.
    mutating func execute(
        _ command: SoundCommand, prepared: PreparedSound?, completion: (@Sendable () -> Void)? = nil,
        on channel: ChannelState, sampleRate: Int, events: inout [@Sendable () -> Void]
    ) {
        switch command {
        case .null:
            break
        case .flush:
            channel.queue.removeAll()
        case .quiet:
            channel.voice = nil
        case .reInit(let bits):
            channel.interpolates = !bits.contains(.noInterpolation)
        case .wait(let halfMilliseconds):
            let frames = Int(Double(max(0, halfMilliseconds)) * Double(sampleRate) / 2000)
            channel.waitRemaining = frames > 0 ? frames : nil
        case .pause:
            channel.isQueuePaused = true
        case .resume:
            channel.isQueuePaused = false
        case .callBack:
            let callBack = channel.callBack
            let handle = channel.handle
            events.append { if let handle, let callBack { callBack(handle, command) } }
        case .sync(let count, let identifier):
            guard count > 1 else { break }
            channel.syncIdentifier = identifier
            var group = syncGroups[identifier, default: []]
            group.append(channel)
            if group.count >= Int(count) {
                pendingReleases.append(contentsOf: group)
                syncGroups[identifier] = nil
            } else {
                syncGroups[identifier] = group
            }
        case .buffer:
            guard let prepared else { break }
            if prepared.frames > 0 {
                channel.voice = Voice(sound: prepared, completion: completion)
                channel.loopOverride = nil
            } else if let completion {
                channel.voice = nil
                events.append(completion)
            }
        case .amplitude(let value):
            channel.gain = min(Double(max(value, 0)) / 256, ChannelState.maximumGain)
        case .volume(let left, let right):
            let sum = Int(left) + Int(right)
            channel.pan = sum == 0 ? 0 : 2 * Double(right) / Double(sum) - 1
            channel.gain = min(Double(max(left, right)) / 256, ChannelState.maximumGain)
        case .frequency(let note):
            channel.playbackNote = note
        case .rate(let value), .rateMultiplier(let value):
            channel.pitchMultiplier = Double(value) / 65536
        case .loop(let on):
            channel.loopOverride = on
        case .pausePlayback:
            channel.voice?.isPaused = true
        case .resumePlayback:
            channel.voice?.isPaused = false
        }
    }

    /// Runs a channel's queued commands until one holds it up.
    private mutating func runQueue(_ channel: ChannelState, sampleRate: Int, events: inout [@Sendable () -> Void]) {
        while !channel.isQueuePaused, channel.voice == nil, channel.waitRemaining == nil, channel.syncIdentifier == nil,
              !channel.queue.isEmpty {
            let next = channel.queue.removeFirst()
            execute(next.command, prepared: next.prepared, on: channel, sampleRate: sampleRate, events: &events)
        }
    }

    /// Moves a channel `frames` frames on, mixing its sound into the buffer
    /// from `offset` and running its commands as they come up.
    mutating func advance(
        _ channel: ChannelState, frames: Int, into buffer: UnsafeMutableBufferPointer<Float>, at offset: Int,
        sampleRate: Int, events: inout [@Sendable () -> Void]
    ) {
        var remaining = frames
        var position = offset
        var turns = 0
        while remaining > 0, turns < 10_000 {
            turns += 1
            runQueue(channel, sampleRate: sampleRate, events: &events)
            var span = remaining
            if let wait = channel.waitRemaining { span = min(span, wait) }
            var advanced = span
            if var voice = channel.voice, !voice.isPaused {
                let pitch = channel.pitchMultiplier * MIDINote.frequency(of: channel.playbackNote)
                    / MIDINote.frequency(of: voice.sound.baseNote)
                let step = max(0.001, voice.sound.sampleRate / Double(sampleRate) * pitch)
                let left = Float(channel.gain * (channel.pan <= 0 ? 1 : 1 - channel.pan))
                let right = Float(channel.gain * (channel.pan >= 0 ? 1 : 1 + channel.pan))
                // A channel on its way out plays a loop once: nothing is left to stop it.
                let looping = !channel.retiresWhenIdle && (channel.loopOverride ?? (voice.sound.loop != nil))
                let result = Self.mix(&voice, frames: span, step: step, left: left, right: right,
                                      interpolates: channel.interpolates, looping: looping, into: buffer, at: position)
                if result.ended {
                    channel.voice = nil
                    if let completion = voice.completion { events.append(completion) }
                    advanced = result.produced
                } else {
                    channel.voice = voice
                }
            }
            if let wait = channel.waitRemaining {
                channel.waitRemaining = wait > advanced ? wait - advanced : nil
            }
            if advanced == 0 && channel.voice == nil && channel.queue.isEmpty { break }
            // A channel with nothing to run goes quiet for the rest of the slice.
            if channel.voice == nil && channel.waitRemaining == nil && (channel.queue.isEmpty || channel.isQueuePaused || channel.syncIdentifier != nil) {
                break
            }
            position += advanced
            remaining -= advanced
        }
    }

    /// Adds up to `frames` frames of a voice to the buffer, resampled at a
    /// step of source frames a frame, panned by the gains. Returns the frames
    /// it added, and whether the sound ended.
    private static func mix(
        _ voice: inout Voice, frames: Int, step: Double, left: Float, right: Float, interpolates: Bool, looping: Bool,
        into buffer: UnsafeMutableBufferPointer<Float>, at offset: Int
    ) -> (produced: Int, ended: Bool) {
        let sound = voice.sound
        let count = sound.frames
        let region = sound.loop ?? 0 ..< count
        let regionStart = Double(region.lowerBound), regionEnd = Double(region.upperBound)
        var position = voice.position
        var produced = 0
        var ended = false
        let scale: Float = 1 / 32768
        sound.samples.withUnsafeBufferPointer { samples in
            while produced < frames {
                if looping {
                    if position >= regionEnd {
                        position = regionStart + (position - regionStart).truncatingRemainder(dividingBy: Double(region.count))
                    }
                } else if position >= Double(count) {
                    ended = true
                    break
                }
                let index = Int(position)
                let base = index * sound.channels
                var l = Float(samples[base])
                var r = sound.channels > 1 ? Float(samples[base + 1]) : l
                let fraction = Float(position - Double(index))
                if interpolates, fraction > 0 {
                    var next = index + 1
                    if looping {
                        if next >= region.upperBound { next = region.lowerBound }
                    } else if next >= count {
                        next = index
                    }
                    let nextBase = next * sound.channels
                    let l2 = Float(samples[nextBase])
                    let r2 = sound.channels > 1 ? Float(samples[nextBase + 1]) : l2
                    l += (l2 - l) * fraction
                    r += (r2 - r) * fraction
                }
                buffer[(offset + produced) * 2] += l * scale * left
                buffer[(offset + produced) * 2 + 1] += r * scale * right
                position += step
                produced += 1
            }
        }
        if !looping && position >= Double(count) { ended = true }
        voice.position = position
        return (produced, ended)
    }
}
