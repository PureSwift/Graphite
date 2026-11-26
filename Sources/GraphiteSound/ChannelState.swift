// What a channel plays and where it is: the sound as 16-bit frames ready to
// mix, the voice playing it, and the channel's settings and queue. Used only
// with the mixer's lock held.
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

import GraphiteBase

/// A sound decoded and checked, so that playing it can't fail.
struct PreparedSound {

    /// The frames' samples, a frame's channels after another.
    var samples: [Int16]
    var channels: Int
    var frames: Int
    var sampleRate: Double
    var baseNote: Int

    /// The frames to repeat: a loop the sound's header has that is two frames
    /// or more, and ends no later than the sound does.
    var loop: Range<Int>?

    /// The rate of a sound that says none: 22254.54545, the rate of the
    /// original Macintosh's 22 kHz.
    static let defaultSampleRate = 22254.545

    init(_ sound: SampledSound) throws(MacError) {
        let samples = try sound.pcm16()
        // pcm16 has refused a sound with no channels.
        channels = sound.channels
        frames = samples.count / sound.channels
        self.samples = samples
        sampleRate = sound.sampleRate > 0 ? sound.sampleRate : Self.defaultSampleRate
        baseNote = sound.baseNote
        if let loop = sound.loop {
            let start = max(loop.lowerBound, 0)
            let end = min(loop.upperBound, frames)
            self.loop = end - start >= 2 ? start ..< end : nil
        }
    }
}

/// A sound playing in a channel.
struct Voice {
    var sound: PreparedSound

    /// The frame about to play, with a fraction of one.
    var position = 0.0

    var isPaused = false

    /// Called when the sound plays to its end; not when it is stopped.
    var completion: (@Sendable () -> Void)?
}

/// A channel's state. The mixer's lock guards it, which is why it is safe to
/// hand around.
final class ChannelState: @unchecked Sendable {

    /// The most commands a queue holds.
    static let queueCapacity = 128

    /// The most a channel amplifies a sound by.
    static let maximumGain = 2.5

    /// The handle the program has; the callback is called with it.
    weak var handle: SoundChannel?

    var callBack: (@Sendable (SoundChannel, SoundCommand) -> Void)?

    var queue: [(command: SoundCommand, prepared: PreparedSound?)] = []

    var voice: Voice?

    /// pauseCmd was run and resumeCmd hasn't been.
    var isQueuePaused = false

    /// The frames a waitCmd has left.
    var waitRemaining: Int?

    /// The identifier of the syncCmd the channel waits at.
    var syncIdentifier: Int32?

    var gain = 1.0
    var pan = 0.0
    var playbackNote = 60
    var pitchMultiplier = 1.0
    var interpolates = true

    /// What loopCmd said, which stands until the next sound; nil goes by the
    /// sound's header.
    var loopOverride: Bool?

    /// Gone: its commands are errors.
    var isDisposed = false

    /// To be gone when it has nothing left to do (SndDisposeChannel with
    /// quietNow false).
    var retiresWhenIdle = false

    var isIdle: Bool {
        voice == nil && queue.isEmpty && waitRemaining == nil && syncIdentifier == nil
    }
}
