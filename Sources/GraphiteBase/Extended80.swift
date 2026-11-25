// SANE's 80-bit extended numbers, as the Sound Manager's sample rates and
// AIFF files keep them: a sign and a 15-bit exponent in one word, then a
// 64-bit mantissa with its leading one, most significant word first.

public struct Extended80: Hashable, Sendable {

    /// The sign in the high bit, the exponent, biased by 16383, below it.
    public var signAndExponent: UInt16

    /// The mantissa, its integer bit at the top.
    public var mantissa: UInt64

    public init(signAndExponent: UInt16, mantissa: UInt64) {
        self.signAndExponent = signAndExponent
        self.mantissa = mantissa
    }

    /// dtox80: the double, exactly. Denormals have their leading one moved
    /// to the mantissa's top; infinities and NaNs keep their kind.
    public init(_ value: Double) {
        let bits = value.bitPattern
        let sign = UInt16(truncatingIfNeeded: bits >> 63) << 15
        var exponent = Int(bits >> 52 & 0x7ff)
        let fraction = bits & 0x000f_ffff_ffff_ffff
        var mantissa: UInt64
        if exponent == 0 && fraction == 0 {
            mantissa = 0
        } else if exponent == 0x7ff {
            exponent = 0x7fff
            mantissa = 1 << 63 | fraction << 11
        } else if exponent == 0 {
            mantissa = fraction << 11
            exponent = 16383 - 1022
            while mantissa >> 63 == 0 {
                mantissa <<= 1
                exponent -= 1
            }
        } else {
            mantissa = 1 << 63 | fraction << 11
            exponent += 16383 - 1023
        }
        self.signAndExponent = sign | UInt16(exponent)
        self.mantissa = mantissa
    }

    /// The ten bytes as they're stored: the word of sign and exponent, then
    /// the mantissa, big-endian.
    public init?(bytes: some Collection<UInt8>) {
        guard bytes.count == 10 else { return nil }
        let array = Array(bytes)
        self.signAndExponent = UInt16(array[0]) << 8 | UInt16(array[1])
        self.mantissa = array[2...].reduce(0) { $0 << 8 | UInt64($1) }
    }

    public var isNegative: Bool { signAndExponent & 0x8000 != 0 }

    /// The exponent, without its bias.
    public var exponent: Int { Int(signAndExponent & 0x7fff) - 16383 }

    public var bytes: [UInt8] {
        var bytes = [UInt8(signAndExponent >> 8), UInt8(truncatingIfNeeded: signAndExponent)]
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: mantissa >> UInt64(shift)))
        }
        return bytes
    }

    /// x80tod: the nearest double, infinity past the largest.
    public var doubleValue: Double {
        let sign: FloatingPointSign = isNegative ? .minus : .plus
        if signAndExponent & 0x7fff == 0x7fff {
            return mantissa << 1 == 0 ? Double(sign: sign, exponent: 0, significand: .infinity) : .nan
        }
        guard mantissa != 0 else { return isNegative ? -0.0 : 0.0 }
        // The exponent of the mantissa's highest one, which an unnormal
        // number has below the top.
        let leading = exponent - mantissa.leadingZeroBitCount
        if leading > Double.greatestFiniteMagnitude.exponent {
            return Double(sign: sign, exponent: 0, significand: .infinity)
        }
        if leading < Double.leastNonzeroMagnitude.exponent - 1 {
            return Double(sign: sign, exponent: 0, significand: 0)
        }
        return Double(sign: sign, exponent: exponent - 63, significand: Double(mantissa))
    }
}
