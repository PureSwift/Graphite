import Testing
import GraphiteBase

@Suite struct FixedTests {

    @Test func conversions() {
        #expect(Fixed(1.5).rawValue == 0x0001_8000)
        #expect(Fixed(-1.5).rawValue == -0x0001_8000)
        #expect(Fixed(3).rawValue == 0x0003_0000)
        #expect(Fixed(rawValue: 0x0002_4000).doubleValue == 2.25)
        #expect(Fixed(1e10).rawValue == .max)
        #expect(Fixed(-1e10).rawValue == .min)
        #expect(Fixed(100_000).rawValue == .max)
        #expect(Fixed(Double.nan).rawValue == 0)
    }

    @Test func rounding() {
        #expect(Fixed(2.5).roundedInteger == 3)
        #expect(Fixed(2.49).roundedInteger == 2)
        #expect(Fixed(-2.5).roundedInteger == -2)
        #expect(Fixed(-2.51).roundedInteger == -3)
        #expect(Fixed(7.6).rounded == 8)
    }

    @Test func arithmetic() {
        #expect(Fixed(2) * Fixed(1.5) == Fixed(3))
        #expect(Fixed(-2) * Fixed(1.5) == Fixed(-3))
        #expect(Fixed(3) / Fixed(2) == Fixed(1.5))
        #expect(Fixed(1) + Fixed(0.25) == Fixed(1.25))
        #expect(Fixed(1) - Fixed(0.25) == Fixed(0.75))
        #expect(Fixed(ratio: 1, 3).rawValue == 0x5555)
        #expect(Fixed(ratio: 2, 3).rawValue == 0xAAAB)
        #expect(Fixed(ratio: -1, 3).rawValue == -0x5555)
    }

    @Test func saturation() {
        #expect(Fixed(30000) * Fixed(30000) == Fixed(rawValue: .max))
        #expect(Fixed(-30000) * Fixed(30000) == Fixed(rawValue: .min))
        #expect(Fixed(1) / Fixed.zero == Fixed(rawValue: .max))
        #expect(Fixed(-1) / Fixed.zero == Fixed(rawValue: .min))
        #expect(Fixed(rawValue: .max) + Fixed(1) == Fixed(rawValue: .max))
    }

    @Test func fract() {
        #expect(Fract(0.5).rawValue == 0x2000_0000)
        #expect(Fract.one.doubleValue == 1)
        #expect(Fract(0.5) * Fract(0.5) == Fract(0.25))
        #expect(Fract(0.25) / Fract(0.5) == Fract(0.5))
        #expect(Fract(3).rawValue == .max)
        #expect(Fract(Fixed(0.75)) == Fract(0.75))
        #expect(Fract(0.75).fixed == Fixed(0.75))
    }
}

@Suite struct Extended80Tests {

    @Test func aiffSampleRates() {
        #expect(Extended80(44100).bytes == [0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0])
        #expect(Extended80(22050).bytes == [0x40, 0x0D, 0xAC, 0x44, 0, 0, 0, 0, 0, 0])
        #expect(Extended80(22254.545454545454).bytes.prefix(4) == [0x40, 0x0D, 0xAD, 0xDD])
        #expect(Extended80(bytes: [0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0])?.doubleValue == 44100)
        #expect(Extended80(bytes: [0x40]) == nil)
    }

    @Test func roundTrips() {
        let values: [Double] = [0, -0.0, 1, -1, 0.5, 3.141592653589793, 1e-300, -1e300, .leastNonzeroMagnitude,
                                .leastNormalMagnitude, .greatestFiniteMagnitude, 5e-324 * 3, .infinity, -.infinity]
        for value in values {
            let extended = Extended80(value)
            #expect(extended.doubleValue == value, "\(value)")
            #expect(extended.doubleValue.sign == value.sign, "\(value)")
            #expect(Extended80(bytes: extended.bytes) == extended)
        }
        #expect(Extended80(Double.nan).doubleValue.isNaN)
    }

    @Test func normalizesDenormals() {
        let extended = Extended80(Double.leastNonzeroMagnitude)
        #expect(extended.mantissa == 1 << 63)
        #expect(extended.exponent == -1074)
    }

    @Test func beyondDouble() {
        // 2^2000 is past a double's range.
        #expect(Extended80(signAndExponent: 16383 + 2000, mantissa: 1 << 63).doubleValue == .infinity)
        #expect(Extended80(signAndExponent: 0x8000 | (16383 + 2000), mantissa: 1 << 63).doubleValue == -.infinity)
        #expect(Extended80(signAndExponent: 1, mantissa: 1 << 63).doubleValue == 0)
    }
}

@Suite struct SANEDecimalTests {

    private func text(_ decimal: SANEDecimal) -> String {
        String(decoding: decimal.digits, as: UTF8.self)
    }

    @Test func floatingForm() {
        let pi = SANEDecimal(3.14159265, form: .floating(digits: 6))
        #expect(text(pi) == "314159")
        #expect(pi.exponent == -5)
        #expect(!pi.isNegative)
        let large = SANEDecimal(-12345678, form: .floating(digits: 3))
        #expect(text(large) == "123")
        #expect(large.exponent == 5)
        #expect(large.isNegative)
        #expect(large.doubleValue == -12300000)
        #expect(text(SANEDecimal(1, form: .floating(digits: 0))) == "1")
        #expect(text(SANEDecimal(1, form: .floating(digits: 99))).count == 36)
    }

    @Test func fixedForm() {
        let money = SANEDecimal(12.345, form: .fixed(digits: 2))
        #expect(text(money) == "1235" || text(money) == "1234")
        #expect(money.exponent == -2)
        let whole = SANEDecimal(0.25, form: .fixed(digits: 0))
        #expect(text(whole) == "0")
        #expect(whole.exponent == 0)
        let small = SANEDecimal(0.05, form: .fixed(digits: 3))
        #expect(text(small) == "50")
        #expect(small.exponent == -3)
        #expect(small.doubleValue == 0.05)
    }

    @Test func zeroKeepsOneDigit() {
        let zero = SANEDecimal(0, form: .floating(digits: 10))
        #expect(text(zero) == "0")
        #expect(zero.exponent == 0)
        #expect(SANEDecimal(-0.0, form: .fixed(digits: 4)).isNegative)
    }

    @Test func longFixedNumbersKeep36Digits() {
        let huge = SANEDecimal(1e40, form: .fixed(digits: 0))
        #expect(huge.digits.count == 36)
        #expect(huge.exponent == 5)
        #expect(abs(huge.doubleValue - 1e40) / 1e40 < 1e-15)
    }

    @Test func specialValues() {
        #expect(text(SANEDecimal(.infinity, form: .floating(digits: 5))) == "I")
        #expect(SANEDecimal(-.infinity, form: .floating(digits: 5)).doubleValue == -.infinity)
        #expect(text(SANEDecimal(.nan, form: .fixed(digits: 2))) == "N")
        #expect(SANEDecimal(.nan, form: .fixed(digits: 2)).doubleValue.isNaN)
        #expect(SANEDecimal(isNegative: false, exponent: 0, digits: []).doubleValue == 0)
    }

    @Test func roundTripsAt17Digits() {
        for value in [1.0, 0.1, 123.456, 6.02214076e23, 1.602176634e-19, -98765.4321] {
            #expect(SANEDecimal(value, form: .floating(digits: 17)).doubleValue == value)
        }
    }
}

@Suite struct QuickDrawRandomTests {

    @Test func parkMillerSequence() {
        var random = QuickDrawRandom()
        // 16807, then 16807² mod (2³¹ − 1) = 282475249, whose low 16 bits are 0x3AF1.
        #expect(random.next() == 16807)
        #expect(random.seed == 16807)
        #expect(random.next() == 0x3AF1)
        #expect(random.seed == 282_475_249)
    }

    @Test func seedRepeatsSequence() {
        var a = QuickDrawRandom(seed: 12345), b = QuickDrawRandom(seed: 12345)
        for _ in 0 ..< 100 { #expect(a.next() == b.next()) }
    }

    @Test func neverMinimum() {
        var random = QuickDrawRandom(seed: 99)
        for _ in 0 ..< 10000 { #expect(random.next() != .min) }
    }
}
