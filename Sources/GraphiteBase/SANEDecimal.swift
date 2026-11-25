// SANE's decimal records: a number as up to 36 decimal digits, a sign and a
// power of ten, as num2dec makes them for printing and dec2num reads them
// back. A decform asks for a number of significant digits (floating) or of
// digits after the point (fixed).

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// How num2dec writes a number.
public enum DecimalForm: Hashable, Sendable {

    /// FLOATDECIMAL: this many significant digits, 1 to 36.
    case floating(digits: Int)

    /// FIXEDDECIMAL: this many digits after the point, 0 to 80.
    case fixed(digits: Int)
}

/// A number as decimal digits: the digits × 10^exponent, negative when
/// `isNegative`.
public struct SANEDecimal: Hashable, Sendable {

    /// The most digits a record holds.
    public static var maximumDigits: Int { 36 }

    public var isNegative: Bool

    public var exponent: Int16

    /// ASCII digits, most significant first; "N" for a NaN and "I" for an
    /// infinity.
    public var digits: [UInt8]

    public init(isNegative: Bool, exponent: Int16, digits: [UInt8]) {
        self.isNegative = isNegative
        self.exponent = exponent
        self.digits = Array(digits.prefix(Self.maximumDigits))
    }

    /// num2dec: the number, rounded as the form asks. Leading zeros are
    /// dropped, but zero keeps its one digit, with an exponent of zero.
    /// A fixed form with more digits than a record holds keeps the first
    /// 36, the exponent taking the rest.
    public init(_ value: Double, form: DecimalForm) {
        self.isNegative = value.sign == .minus
        self.exponent = 0
        let magnitude = value.magnitude
        guard magnitude.isFinite else {
            self.digits = [magnitude.isNaN ? UInt8(ascii: "N") : UInt8(ascii: "I")]
            return
        }
        var text: [UInt8]
        switch form {
        case .fixed(let count):
            let places = min(max(count, 0), 80)
            text = format("%.*f", Int32(places), magnitude)
            text.removeAll { $0 == UInt8(ascii: ".") }
            exponent = Int16(-places)
        case .floating(let count):
            let significant = min(max(count, 1), Self.maximumDigits)
            text = format("%.*e", Int32(significant - 1), magnitude)
            var power = 0
            if let e = text.firstIndex(of: UInt8(ascii: "e")) {
                power = Int(MacRoman.decode(text[(e + 1)...])) ?? 0
                text.removeSubrange(e...)
            }
            text.removeAll { $0 == UInt8(ascii: ".") }
            exponent = Int16(power - (significant - 1))
        }
        while text.count > 1, text.first == UInt8(ascii: "0") { text.removeFirst() }
        if text.count > Self.maximumDigits {
            exponent += Int16(text.count - Self.maximumDigits)
            text.removeLast(text.count - Self.maximumDigits)
        }
        if text == [UInt8(ascii: "0")] { exponent = 0 }
        self.digits = text
    }

    /// dec2num: the double the record stands for. No digits is zero.
    public var doubleValue: Double {
        guard let first = digits.first else { return 0 }
        if first == UInt8(ascii: "I") { return isNegative ? -.infinity : .infinity }
        if first == UInt8(ascii: "N") { return .nan }
        let value = Double(MacRoman.decode(digits) + "e\(exponent)") ?? 0
        return isNegative ? -value : value
    }
}

/// The C library's printf of one precision and one double.
private func format(_ format: StaticString, _ precision: Int32, _ value: Double) -> [UInt8] {
    var buffer = [CChar](repeating: 0, count: 512)
    let count = withVaList([precision, value]) { arguments in
        format.withUTF8Buffer { pattern in
            pattern.withMemoryRebound(to: CChar.self) { pattern in
                vsnprintf(&buffer, buffer.count, pattern.baseAddress!, arguments)
            }
        }
    }
    return buffer.prefix(Int(max(0, min(count, Int32(buffer.count - 1))))).map { UInt8(bitPattern: $0) }
}
