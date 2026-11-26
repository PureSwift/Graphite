// The commands a sound channel takes: what SndDoCommand queues and
// SndDoImmediate runs at once, and the init bits and synthesizers a channel
// is made with.

import GraphiteBase

/// A channel's init bits (SndNewChannel's `init`, and reInitCmd's).
public struct SoundInit: OptionSet, Hashable, Sendable {

    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// initNoInterp: resample without interpolating between samples.
    public static var noInterpolation: SoundInit { SoundInit(rawValue: 0x0004) }
    /// initNoDrop: no drop-sample conversion.
    public static var noDrop: SoundInit { SoundInit(rawValue: 0x0008) }
    /// initMono.
    public static var mono: SoundInit { SoundInit(rawValue: 0x0080) }
    /// initStereo.
    public static var stereo: SoundInit { SoundInit(rawValue: 0x00C0) }
    /// initMACE3: 3:1 compression.
    public static var mace3: SoundInit { SoundInit(rawValue: 0x0300) }
    /// initMACE6: 6:1 compression.
    public static var mace6: SoundInit { SoundInit(rawValue: 0x0400) }
}

/// The synthesizers a channel can be made for: only sampled sounds are played.
public enum SoundSynth: Int16, Hashable, Sendable {
    case squareWave = 1
    case waveTable = 3
    case sampled = 5
}

/// A sound command. A channel runs its queued commands in order: a
/// sampled sound holds the queue until it has played, a wait holds it for its
/// time, a sync until the other channels of the sync reach it, and the rest
/// run as they are reached. Immediate commands run at once.
public enum SoundCommand: Hashable, Sendable {

    /// nullCmd.
    case null

    /// quietCmd: stops the sound that is playing. The queue goes on.
    case quiet

    /// flushCmd: empties the queue.
    case flush

    /// reInitCmd: the channel's init bits again, of which interpolation is
    /// the one used.
    case reInit(SoundInit)

    /// waitCmd: nothing, for a time in half-milliseconds.
    case wait(halfMilliseconds: Int)

    /// pauseCmd: the queue holds still. The sound that is playing goes on.
    case pause

    /// resumeCmd: the queue goes on.
    case resume

    /// callBackCmd: the channel's callback is called with the command.
    case callBack(param1: Int16, param2: Int32)

    /// syncCmd: waits until `count` channels have reached a sync of the same
    /// identifier, then they all go on together.
    case sync(count: Int16, identifier: Int32)

    /// bufferCmd and soundCmd: plays a sound, stopping the one that was playing.
    case buffer(SampledSound)

    /// ampCmd: the channel's amplitude, 256 for as recorded.
    case amplitude(Int)

    /// volumeCmd: the left and right volumes, 256 for as recorded; the channel
    /// plays at the louder, panned toward the louder.
    case volume(left: UInt16, right: UInt16)

    /// freqCmd: the MIDI note to play the sound at; its own base note plays it
    /// as recorded.
    case frequency(note: Int)

    /// rateCmd: the playback rate as a 16.16 multiplier of the sound's.
    case rate(Int32)

    /// rateMultiplierCmd: the same.
    case rateMultiplier(Int32)

    /// Repeats the sound whole, or as its loop says, until it is stopped
    /// (false stops a loop the sound's header sets).
    case loop(Bool)

    /// Holds the sound that is playing where it is, as SndPauseFilePlay does.
    case pausePlayback

    /// Goes on from where the sound was held.
    case resumePlayback

    /// The command of a command word and its two parameters, for the ones
    /// that carry no sound: nil for bufferCmd and soundCmd, which point at a
    /// sound, and for a command that isn't here. The word's high bit, which
    /// says an 'snd ' resource has data for it, is ignored.
    public init?(code: UInt16, param1: Int16, param2: Int32) {
        switch code & 0x7FFF {
        case 0: self = .null
        case 3: self = .quiet
        case 4: self = .flush
        case 5: self = .reInit(SoundInit(rawValue: UInt32(bitPattern: param2)))
        case 10: self = .wait(halfMilliseconds: Int(param1))
        case 11: self = .pause
        case 12: self = .resume
        case 13: self = .callBack(param1: param1, param2: param2)
        case 14: self = .sync(count: param1, identifier: param2)
        case 42: self = .frequency(note: Int(param2))
        case 43: self = .amplitude(Int(param1))
        case 46: self = .volume(left: UInt16(truncatingIfNeeded: param2), right: UInt16(truncatingIfNeeded: param2 >> 16))
        case 82: self = .rate(param2)
        case 86: self = .rateMultiplier(param2)
        default: return nil
        }
    }
}
