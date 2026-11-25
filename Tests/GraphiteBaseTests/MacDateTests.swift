#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import Testing
import GraphiteBase

/// In New York's time zone, which has daylight saving time. Serialized,
/// as the zone is the process's.
@Suite(.serialized) struct MacDateTests {

    init() {
        setenv("TZ", "America/New_York", 1)
        tzset()
    }

    @Test func epoch() {
        let date = MacDate(seconds: 0)
        #expect(date.parts == DateParts(year: 1904, month: 1, day: 1, dayOfWeek: 6))
        #expect(MacDate(DateParts(year: 1904, month: 1, day: 1)).seconds == 0)
    }

    @Test(arguments: [
        (DateParts(year: 1950, month: 6, day: 15, hour: 13, minute: 45, second: 30, dayOfWeek: 5), Int64(1_465_998_330), Int16(166)),
        (DateParts(year: 2000, month: 2, day: 29, hour: 23, minute: 59, second: 59, dayOfWeek: 3), Int64(3_034_713_599), Int16(60)),
        (DateParts(year: 2100, month: 3, day: 1, dayOfWeek: 2), Int64(6_190_387_200), Int16(60)),
        (DateParts(year: 2040, month: 2, day: 6, hour: 6, minute: 28, second: 15, dayOfWeek: 2), Int64(4_294_967_295), Int16(37)),
    ])
    func partsRoundTrip(parts: DateParts, seconds: Int64, dayOfYear: Int16) {
        #expect(MacDate(parts).seconds == seconds)
        let date = MacDate(seconds: seconds)
        #expect(date.parts == parts)
        #expect(date.longParts.dayOfYear == dayOfYear)
        #expect(date.longParts.parts == parts)
    }

    @Test func beforeTheEpoch() {
        let parts = DateParts(year: 1900, month: 12, day: 31, hour: 12, dayOfWeek: 2)
        let date = MacDate(parts)
        #expect(date.seconds == -94_651_200)
        #expect(date.parts == parts)
    }

    @Test func outOfRangePartsCarry() {
        #expect(MacDate(DateParts(year: 1999, month: 13, day: 1)) == MacDate(DateParts(year: 2000, month: 1, day: 1)))
        #expect(MacDate(DateParts(year: 2000, month: 1, day: 32)) == MacDate(DateParts(year: 2000, month: 2, day: 1)))
        #expect(MacDate(DateParts(year: 2000, month: 3, day: 0)) == MacDate(DateParts(year: 2000, month: 2, day: 29)))
        #expect(MacDate(DateParts(year: 2000, month: 1, day: 1, hour: 25)) == MacDate(DateParts(year: 2000, month: 1, day: 2, hour: 1)))
    }

    @Test func classicSecondsWrapIn2040() {
        let last = MacDate(classicSeconds: .max)
        #expect(last.parts.year == 2040)
        #expect(MacDate(seconds: Int64(UInt32.max) + 1).classicSeconds == 0)
    }

    @Test func longParts() {
        let parts = MacDate(DateParts(year: 2024, month: 7, day: 3, hour: 17, minute: 46, second: 40)).longParts
        #expect(parts.pm == 1)
        #expect(parts.dayOfYear == 185)
        #expect(parts.weekOfYear == 27)
        #expect(parts.dayOfWeek == 4)
        #expect(parts.era == 0)
    }

    @Test func daylightSavingTime() {
        let summer = MacDate(unixTime: 1_720_000_000)
        #expect(summer.parts == DateParts(year: 2024, month: 7, day: 3, hour: 5, minute: 46, second: 40, dayOfWeek: 4))
        #expect(summer.unixTime == 1_720_000_000)
        let winter = MacDate(unixTime: 1_704_067_200)
        #expect(winter.parts == DateParts(year: 2023, month: 12, day: 31, hour: 19, dayOfWeek: 1))
        #expect(winter.unixTime == 1_704_067_200)
        #expect(LocalTime.offset(atUnixTime: 1_720_000_000) == (-14400, true))
        #expect(LocalTime.offset(atUnixTime: 1_704_067_200) == (-18000, false))
    }

    @Test func utcConversions() {
        let utc = Int64(1_720_000_000) + MacDate.unixEpochOffset
        let local = MacDate(utcSeconds: utc)
        #expect(local.seconds == utc - 14400)
        #expect(local.utcSeconds == utc)
    }

    @Test func beforeUnixTime() {
        // 1950: no daylight saving time in January.
        let date = MacDate(unixTime: -630_720_000)
        #expect(date.unixTime == -630_720_000)
        #expect(date.seconds == -630_720_000 + MacDate.unixEpochOffset - 18000)
    }

    @Test func machineLocation() {
        let location = MachineLocation(gmtDelta: -18000, isDaylightSaving: false)
        #expect(location.packedGMTDelta == Int32(bitPattern: 0x00FF_B9B0))
        let summer = MachineLocation(gmtDelta: -14400, isDaylightSaving: true)
        #expect(summer.packedGMTDelta == Int32(bitPattern: 0x80FF_C7C0))
        let current = MachineLocation.current
        #expect(current.gmtDelta == -18000 || current.gmtDelta == -14400)
    }
}

@Suite struct SystemClockTests {

    @Test func clocksAdvanceTogether() {
        let nanoseconds = SystemClock.nanoseconds
        let microseconds = SystemClock.microseconds
        let ticks = SystemClock.ticks
        #expect(microseconds >= nanoseconds / 1000)
        #expect(UInt64(ticks) <= (SystemClock.nanoseconds * 60 / 1_000_000_000) & 0xffff_ffff)
        #expect(SystemClock.doubleClickTicks == 30)
    }
}
