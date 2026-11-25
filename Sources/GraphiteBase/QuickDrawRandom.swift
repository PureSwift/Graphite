// QuickDraw's Random: the Park–Miller generator over its randSeed global,
// a 16-bit number from each step.

public struct QuickDrawRandom: Hashable, Sendable {

    /// randSeed, which a program may set to repeat a sequence. QuickDraw
    /// starts it at 1.
    public var seed: UInt32

    public init(seed: UInt32 = 1) {
        self.seed = seed
    }

    /// Random: the next number, from -32767 to 32767.
    public mutating func next() -> Int16 {
        seed = UInt32((UInt64(seed) * 16807) % 0x7fff_ffff)
        let value = Int16(truncatingIfNeeded: seed)
        return value == .min ? 0 : value
    }
}
