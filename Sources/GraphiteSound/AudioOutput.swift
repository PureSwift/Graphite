// Where a mixer's frames go: an audio device the host provides.

/// A device that takes the mixer's output. The host implements it over
/// whatever it plays sound with.
public protocol AudioOutput: AnyObject, Sendable {

    /// The frames a second the device plays at, which the mixer renders at.
    var sampleRate: Int { get }

    /// Starts playing: the device calls `render` with a buffer to fill for
    /// each block it needs, of stereo frames, left then right, as floats of
    /// -1 to 1.
    func start(render: @escaping @Sendable (UnsafeMutableBufferPointer<Float>) -> Void)

    /// Stops playing and lets go of the `render` it was given.
    func stop()
}
