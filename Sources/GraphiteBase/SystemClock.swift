// The clocks a Mac program reads: ticks, sixtieths of a second since the
// system started (TickCount), microseconds (Microseconds) and nanoseconds
// (UpTime), all from the monotonic clock; and the user's double-click and
// caret-blink times.

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

public enum SystemClock {

    /// Nanoseconds of the monotonic clock: since boot on Linux.
    public static var nanoseconds: UInt64 {
        var time = timespec()
        clock_gettime(CLOCK_MONOTONIC, &time)
        return UInt64(time.tv_sec) * 1_000_000_000 + UInt64(time.tv_nsec)
    }

    /// Microseconds: the monotonic clock in microseconds.
    public static var microseconds: UInt64 { nanoseconds / 1000 }

    /// TickCount: the monotonic clock in sixtieths of a second, wrapping
    /// at 32 bits.
    public static var ticks: UInt32 { UInt32(truncatingIfNeeded: nanoseconds * 60 / 1_000_000_000) }

    /// GetDblTime: the longest time between a double click's clicks, in
    /// ticks; half a second, the Mac's usual setting.
    public static var doubleClickTicks: UInt32 { 30 }

    /// GetCaretTime: the time between the caret's blinks, in ticks.
    public static var caretBlinkTicks: UInt32 { 30 }
}
