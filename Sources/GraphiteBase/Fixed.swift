// The Toolbox's fixed-point numbers: Fixed, 16.16, for QuickDraw's and the
// Sound Manager's fractions, and Fract, 2.30, for numbers between -2 and 2.
// Arithmetic rounds to the nearest and saturates, as FixMul, FixDiv,
// FracMul and FracDiv do: a result too large for 32 bits is the largest or
// smallest number, and division by zero is one of those, by the
// dividend's sign.

/// A signed 16.16 fixed-point number.
public struct Fixed: RawRepresentable, Hashable, Comparable, Sendable {

    public var rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// Long2Fix: the integer, saturating.
    public init(_ integer: Int) {
        self.rawValue = saturate(Int64(clamping: integer) << 16)
    }

    /// X2Fix: the nearest number, saturating.
    public init(_ value: Double) {
        self.rawValue = saturate(value * 65536)
    }

    /// FixRatio: numerator over denominator.
    public init(ratio numerator: Int16, _ denominator: Int16) {
        self = Fixed(Int(numerator)) / Fixed(Int(denominator))
    }

    public static var zero: Fixed { Fixed(rawValue: 0) }

    public static var one: Fixed { Fixed(rawValue: 0x0001_0000) }

    /// Fix2X.
    public var doubleValue: Double { Double(rawValue) / 65536 }

    /// Fix2Long: the nearest integer, halves rounded up.
    public var roundedInteger: Int32 { Int32(truncatingIfNeeded: (Int64(rawValue) + 0x8000) >> 16) }

    /// FixRound: the same, as a 16-bit integer.
    public var rounded: Int16 { Int16(truncatingIfNeeded: roundedInteger) }

    /// FixMul.
    public static func * (lhs: Fixed, rhs: Fixed) -> Fixed {
        Fixed(rawValue: multiply(lhs.rawValue, rhs.rawValue, shift: 16))
    }

    /// FixDiv.
    public static func / (lhs: Fixed, rhs: Fixed) -> Fixed {
        Fixed(rawValue: divide(lhs.rawValue, rhs.rawValue, shift: 16))
    }

    public static func + (lhs: Fixed, rhs: Fixed) -> Fixed {
        Fixed(rawValue: saturate(Int64(lhs.rawValue) + Int64(rhs.rawValue)))
    }

    public static func - (lhs: Fixed, rhs: Fixed) -> Fixed {
        Fixed(rawValue: saturate(Int64(lhs.rawValue) - Int64(rhs.rawValue)))
    }

    public static func < (lhs: Fixed, rhs: Fixed) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A signed 2.30 fixed-point number.
public struct Fract: RawRepresentable, Hashable, Comparable, Sendable {

    public var rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    /// X2Frac: the nearest number, saturating.
    public init(_ value: Double) {
        self.rawValue = saturate(value * 1_073_741_824)
    }

    /// Fix2Frac.
    public init(_ fixed: Fixed) {
        self.rawValue = saturate(Int64(fixed.rawValue) << 14)
    }

    public static var zero: Fract { Fract(rawValue: 0) }

    public static var one: Fract { Fract(rawValue: 0x4000_0000) }

    /// Frac2X.
    public var doubleValue: Double { Double(rawValue) / 1_073_741_824 }

    /// Frac2Fix: rounded to the nearest.
    public var fixed: Fixed { Fixed(rawValue: Int32(truncatingIfNeeded: (Int64(rawValue) + 0x2000) >> 14)) }

    /// FracMul.
    public static func * (lhs: Fract, rhs: Fract) -> Fract {
        Fract(rawValue: multiply(lhs.rawValue, rhs.rawValue, shift: 30))
    }

    /// FracDiv.
    public static func / (lhs: Fract, rhs: Fract) -> Fract {
        Fract(rawValue: divide(lhs.rawValue, rhs.rawValue, shift: 30))
    }

    public static func < (lhs: Fract, rhs: Fract) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Arithmetic

private func saturate(_ value: Int64) -> Int32 {
    Int32(clamping: value)
}

private func saturate(_ value: Double) -> Int32 {
    if value.isNaN { return 0 }
    let rounded = value.rounded(.toNearestOrAwayFromZero)
    if rounded >= Double(Int32.max) { return .max }
    if rounded <= Double(Int32.min) { return .min }
    return Int32(rounded)
}

/// (a × b) >> shift, rounded to the nearest.
private func multiply(_ a: Int32, _ b: Int32, shift: Int64) -> Int32 {
    let product = Int64(a) * Int64(b)
    return saturate((product + (1 << (shift - 1))) >> shift)
}

/// (a << shift) / b, rounded to the nearest.
private func divide(_ a: Int32, _ b: Int32, shift: Int64) -> Int32 {
    guard b != 0 else { return a < 0 ? .min : .max }
    let numerator = Int64(a) << shift
    let denominator = Int64(b)
    var quotient = numerator / denominator
    let remainder = numerator % denominator
    // Away from zero when the remainder is at least half the divisor.
    if remainder.magnitude * 2 >= denominator.magnitude {
        quotient += (numerator < 0) == (denominator < 0) ? 1 : -1
    }
    return saturate(quotient)
}
