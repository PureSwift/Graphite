// A sound channel: what a program makes with SndNewChannel to play sounds
// through, and sends commands to.

import GraphiteBase

/// SndChannelStatus.
public struct ChannelStatus: Hashable, Sendable {

    /// scChannelBusy: a sound is playing, or commands are waiting or running.
    public var isBusy: Bool

    /// scChannelPaused: the queue was paused with pauseCmd, or the sound that is
    /// playing is held.
    public var isPaused: Bool

    /// The commands in the queue that haven't run.
    public var queuedCommands: Int

    public init(isBusy: Bool, isPaused: Bool, queuedCommands: Int) {
        self.isBusy = isBusy
        self.isPaused = isPaused
        self.queuedCommands = queuedCommands
    }
}

/// A channel the program lets go of is disposed with `quietNow` false: it
/// plays what it was given, and runs what it had queued, and is then gone.
/// A sound that loops plays through once then, since nothing is left to stop it.
public final class SoundChannel: @unchecked Sendable {

    let mixer: SoundMixer
    let state: ChannelState

    init(mixer: SoundMixer, state: ChannelState) {
        self.mixer = mixer
        self.state = state
    }

    deinit {
        mixer.dispose(state, quietNow: false)
    }

    /// SndChannelStatus.
    public var status: ChannelStatus {
        mixer.status(of: state)
    }

    /// SndDoImmediate: a command run at once, whatever the channel is doing.
    /// `badFormat` or another error of a sound that can't be played;
    /// `badChannel` for a channel that has been disposed.
    public func doImmediate(_ command: SoundCommand) throws(MacError) {
        try mixer.run(command, on: state)
    }

    /// SndDoCommand: a command put at the end of the queue, to run when the
    /// ones before it have. It doesn't wait for room: `queueFull` for a queue
    /// of 128, and the sound of a command that can't be played is refused here,
    /// not when it is reached.
    public func doCommand(_ command: SoundCommand) throws(MacError) {
        try mixer.enqueue(command, on: state)
    }

    /// Plays a sound at once, in place of the one playing, and calls
    /// `completion` when it plays to its end, not if it is stopped first.
    /// SndStartFilePlay and SndPlay do this.
    public func play(_ sound: SampledSound, completion: (@Sendable () -> Void)? = nil) throws(MacError) {
        try mixer.run(.buffer(sound), completion: completion, on: state)
    }

    /// SndDisposeChannel: the channel is gone. With `quietNow` false it first
    /// plays what it is playing and runs what it has queued; a sound that
    /// loops plays through once.
    public func dispose(quietNow: Bool = true) {
        mixer.dispose(state, quietNow: quietNow)
    }
}
