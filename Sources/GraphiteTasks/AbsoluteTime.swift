// Driver Services' and Multiprocessing Services' clock: AbsoluteTime,
// nanoseconds of the monotonic clock here as mach_absolute_time counts
// them on Intel Macs, and Duration, a 32-bit count of milliseconds when
// positive and microseconds when negative.

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import GraphiteBase

/// A moment of the monotonic clock, in nanoseconds (AbsoluteTime and
/// Nanoseconds are the same here).
public struct AbsoluteTime: RawRepresentable, Hashable, Comparable, Sendable {

    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(nanoseconds: UInt64) {
        self.rawValue = nanoseconds
    }

    public var nanoseconds: UInt64 { rawValue }

    /// UpTime: now.
    public static var now: AbsoluteTime { AbsoluteTime(nanoseconds: SystemClock.nanoseconds) }

    /// AddDurationToAbsolute: later by the duration.
    public static func + (lhs: AbsoluteTime, rhs: MacDuration) -> AbsoluteTime {
        AbsoluteTime(nanoseconds: lhs.rawValue &+ rhs.nanoseconds)
    }

    /// AbsoluteDeltaToDuration's nanoseconds: how much later the first is,
    /// zero if it isn't.
    public static func - (lhs: AbsoluteTime, rhs: AbsoluteTime) -> UInt64 {
        lhs.rawValue > rhs.rawValue ? lhs.rawValue - rhs.rawValue : 0
    }

    public static func < (lhs: AbsoluteTime, rhs: AbsoluteTime) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A Duration: milliseconds when positive, microseconds when negative.
public struct MacDuration: RawRepresentable, Hashable, Sendable {

    public var rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// kDurationImmediate: a wait that doesn't wait.
    public static var immediate: MacDuration { MacDuration(rawValue: 0) }

    /// kDurationForever: a wait without end.
    public static var forever: MacDuration { MacDuration(rawValue: 0x7fff_ffff) }

    public static func milliseconds(_ count: Int32) -> MacDuration {
        MacDuration(rawValue: max(count, 0))
    }

    public static func microseconds(_ count: Int32) -> MacDuration {
        MacDuration(rawValue: count <= 0 ? 0 : -count)
    }

    /// AbsoluteToDuration: whole milliseconds from one up, microseconds
    /// below, at most what 31 bits hold.
    public init(nanoseconds: UInt64) {
        if nanoseconds >= 1_000_000 {
            self.rawValue = Int32(clamping: nanoseconds / 1_000_000)
        } else {
            self.rawValue = -Int32(nanoseconds / 1000)
        }
    }

    public var isForever: Bool { rawValue == 0x7fff_ffff }

    /// DurationToAbsolute: the duration in nanoseconds. Forever is its
    /// milliseconds too, as DurationToAbsolute reads it.
    public var nanoseconds: UInt64 {
        rawValue >= 0 ? UInt64(rawValue) * 1_000_000 : UInt64(rawValue.magnitude) * 1000
    }

    /// When a wait of this long that starts now ends; nil for forever.
    var deadline: UInt64? {
        isForever ? nil : SystemClock.nanoseconds &+ nanoseconds
    }
}

/// MPDelayUntil: sleeps until the monotonic clock reaches the time.
public func delay(until time: AbsoluteTime) {
    while true {
        let now = SystemClock.nanoseconds
        guard now < time.rawValue else { return }
        let remaining = time.rawValue - now
        var request = timespec(tv_sec: time_t(remaining / 1_000_000_000), tv_nsec: Int(remaining % 1_000_000_000))
        _ = nanosleep(&request, nil)
    }
}
