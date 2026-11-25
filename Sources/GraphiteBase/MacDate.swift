// The Mac's clock: seconds since the start of 1904, in local time, as
// GetDateTime counts them, and the Date and Time Utilities' records of
// them. Dates are taken apart with the proleptic Gregorian calendar's
// arithmetic, so dates before 1970 and past 2038 work as well as any.

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// A moment as the Mac's clock reads it: seconds since midnight at the
/// start of January 1, 1904, local time.
public struct MacDate: Hashable, Comparable, Sendable {

    /// Seconds from 1904 to 1970.
    public static var unixEpochOffset: Int64 { 2_082_844_800 }

    /// LongDateTime's seconds; GetDateTime's are the low 32 bits.
    public var seconds: Int64

    public init(seconds: Int64) {
        self.seconds = seconds
    }

    /// GetDateTime's unsigned seconds, which run to 2040.
    public init(classicSeconds: UInt32) {
        self.seconds = Int64(classicSeconds)
    }

    /// The local time of a moment in Unix time, by the time zone's offset
    /// then.
    public init(unixTime: Int64) {
        self.seconds = unixTime + Int64(LocalTime.offset(atUnixTime: unixTime).seconds) + Self.unixEpochOffset
    }

    /// The local time of a moment counted in UTC from 1904
    /// (ConvertUTCToLocalTime).
    public init(utcSeconds: Int64) {
        self.init(unixTime: utcSeconds - Self.unixEpochOffset)
    }

    /// DateToSeconds and LongDateToSeconds: the moment of a date's parts,
    /// out-of-range months, days, hours, minutes and seconds carrying into
    /// the next larger part. The day of the week is ignored.
    public init(_ parts: DateParts) {
        var year = Int64(parts.year), month = Int64(parts.month) - 1
        year += floorDivide(month, 12)
        month = floorModulo(month, 12)
        let days = daysFromCivil(year: year, month: month + 1, day: 1) + Int64(parts.day) - 1
        self.seconds = (days - Self.epochDay) * 86400 + Int64(parts.hour) * 3600 + Int64(parts.minute) * 60 + Int64(parts.second)
    }

    /// GetDateTime: now.
    public static var now: MacDate {
        var time = timespec()
        clock_gettime(CLOCK_REALTIME, &time)
        return MacDate(unixTime: Int64(time.tv_sec))
    }

    /// The low 32 bits, as GetDateTime gives them.
    public var classicSeconds: UInt32 { UInt32(truncatingIfNeeded: seconds) }

    /// The moment in Unix time, by the time zone's offset then
    /// (ConvertLocalToUTCTime, less 1970).
    public var unixTime: Int64 {
        let local = seconds - Self.unixEpochOffset
        // The offset at the moment depends on the moment: two guesses
        // settle it except in the hour a clock skips or repeats.
        var guess = local - Int64(LocalTime.offset(atUnixTime: local).seconds)
        guess = local - Int64(LocalTime.offset(atUnixTime: guess).seconds)
        return guess
    }

    /// ConvertLocalToUTCTime: seconds since 1904 in UTC.
    public var utcSeconds: Int64 { unixTime + Self.unixEpochOffset }

    /// SecondsToDate: the date's parts.
    public var parts: DateParts {
        let day = floorDivide(seconds, 86400)
        let time = seconds - day * 86400
        let (year, month, dayOfMonth) = civilFromDays(day + Self.epochDay)
        return DateParts(year: Int16(truncatingIfNeeded: year), month: Int16(month), day: Int16(dayOfMonth),
                         hour: Int16(time / 3600), minute: Int16(time / 60 % 60), second: Int16(time % 60),
                         dayOfWeek: Int16(floorModulo(day + 5, 7) + 1))
    }

    /// LongSecondsToDate: the parts, with the day and week of the year.
    public var longParts: LongDateParts {
        let parts = self.parts
        let day = floorDivide(seconds, 86400) + Self.epochDay
        let dayOfYear = day - daysFromCivil(year: Int64(parts.year), month: 1, day: 1) + 1
        return LongDateParts(era: 0, year: parts.year, month: parts.month, day: parts.day, hour: parts.hour,
                             minute: parts.minute, second: parts.second, dayOfWeek: parts.dayOfWeek,
                             dayOfYear: Int16(dayOfYear), weekOfYear: Int16((dayOfYear - 1) / 7 + 1),
                             pm: parts.hour >= 12 ? 1 : 0)
    }

    public static func < (lhs: MacDate, rhs: MacDate) -> Bool {
        lhs.seconds < rhs.seconds
    }

    /// January 1, 1904, as days from 1970.
    private static let epochDay: Int64 = -24107
}

/// DateTimeRec: a date's parts. Months and days count from 1; the day of
/// the week is 1 for Sunday to 7 for Saturday.
public struct DateParts: Hashable, Sendable {

    public var year: Int16
    public var month: Int16
    public var day: Int16
    public var hour: Int16
    public var minute: Int16
    public var second: Int16
    public var dayOfWeek: Int16

    public init(year: Int16, month: Int16, day: Int16, hour: Int16 = 0, minute: Int16 = 0, second: Int16 = 0, dayOfWeek: Int16 = 0) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.dayOfWeek = dayOfWeek
    }
}

/// LongDateRec: a date's parts with the day and week of the year (from 1)
/// and whether it is after noon. The era is 0, AD.
public struct LongDateParts: Hashable, Sendable {

    public var era: Int16
    public var year: Int16
    public var month: Int16
    public var day: Int16
    public var hour: Int16
    public var minute: Int16
    public var second: Int16
    public var dayOfWeek: Int16
    public var dayOfYear: Int16
    public var weekOfYear: Int16
    public var pm: Int16

    public init(era: Int16, year: Int16, month: Int16, day: Int16, hour: Int16, minute: Int16, second: Int16,
                dayOfWeek: Int16, dayOfYear: Int16, weekOfYear: Int16, pm: Int16) {
        self.era = era
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.dayOfWeek = dayOfWeek
        self.dayOfYear = dayOfYear
        self.weekOfYear = weekOfYear
        self.pm = pm
    }

    public var parts: DateParts {
        DateParts(year: year, month: month, day: day, hour: hour, minute: minute, second: second, dayOfWeek: dayOfWeek)
    }
}

// MARK: - Time zone

/// The local time zone, as the C library's localtime reads it.
public enum LocalTime {

    /// The offset from UTC at a moment, east positive, and whether daylight
    /// saving time is in effect then.
    public static func offset(atUnixTime unixTime: Int64) -> (seconds: Int32, isDaylightSaving: Bool) {
        var time = time_t(clamping: unixTime)
        var parts = tm()
        guard localtime_r(&time, &parts) != nil else { return (0, false) }
        return (Int32(clamping: parts.tm_gmtoff), parts.tm_isdst > 0)
    }
}

/// Where the Mac is (ReadLocation): its latitude and longitude, which are
/// not known here, and its time zone's offset now.
public struct MachineLocation: Hashable, Sendable {

    /// Fract fractions of a great circle; zero here.
    public var latitude: Fract
    public var longitude: Fract

    /// Seconds east of UTC.
    public var gmtDelta: Int32

    public var isDaylightSaving: Bool

    public init(latitude: Fract = .zero, longitude: Fract = .zero, gmtDelta: Int32, isDaylightSaving: Bool) {
        self.latitude = latitude
        self.longitude = longitude
        self.gmtDelta = gmtDelta
        self.isDaylightSaving = isDaylightSaving
    }

    /// The time zone now.
    public static var current: MachineLocation {
        var time = timespec()
        clock_gettime(CLOCK_REALTIME, &time)
        let (offset, daylight) = LocalTime.offset(atUnixTime: Int64(time.tv_sec))
        return MachineLocation(gmtDelta: offset, isDaylightSaving: daylight)
    }

    /// The gmtDelta field as stored: the offset in the low 24 bits, and
    /// daylight saving time's flag in the high byte.
    public var packedGMTDelta: Int32 {
        Int32(bitPattern: UInt32(bitPattern: gmtDelta) & 0x00ff_ffff | (isDaylightSaving ? 0x8000_0000 : 0))
    }
}

// MARK: - Calendar

private func floorDivide(_ a: Int64, _ b: Int64) -> Int64 {
    let quotient = a / b
    return a % b != 0 && (a < 0) != (b < 0) ? quotient - 1 : quotient
}

private func floorModulo(_ a: Int64, _ b: Int64) -> Int64 {
    a - floorDivide(a, b) * b
}

/// Days since 1970-01-01 of a date in the proleptic Gregorian calendar.
private func daysFromCivil(year: Int64, month: Int64, day: Int64) -> Int64 {
    let y = month <= 2 ? year - 1 : year
    let era = floorDivide(y, 400)
    let yearOfEra = y - era * 400
    let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146097 + dayOfEra - 719468
}

/// The date of a day since 1970-01-01.
private func civilFromDays(_ days: Int64) -> (year: Int64, month: Int64, day: Int64) {
    let z = days + 719468
    let era = floorDivide(z, 146097)
    let dayOfEra = z - era * 146097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let mp = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * mp + 2) / 5 + 1
    let month = mp < 10 ? mp + 3 : mp - 9
    return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
}
