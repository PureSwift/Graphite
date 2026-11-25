// Pascal strings: up to 255 MacRoman bytes, which the Toolbox keeps after
// a length byte (Str255, Str63, Str31). Graphite keeps the bytes alone.

/// Up to 255 bytes of MacRoman text.
public struct PascalString: Hashable, Sendable {

    public static var maximumLength: Int { 255 }

    /// The text's bytes, without the length byte; never more than 255.
    public var bytes: [UInt8] {
        didSet {
            if bytes.count > Self.maximumLength { bytes.removeLast(bytes.count - Self.maximumLength) }
        }
    }

    /// The first 255 of the bytes.
    public init(bytes: some Sequence<UInt8>) {
        self.bytes = Array(bytes.prefix(Self.maximumLength))
    }

    public init() {
        self.bytes = []
    }

    /// The text as MacRoman, its first 255 bytes; nil if a character isn't
    /// in MacRoman.
    public init?(_ string: String) {
        guard let bytes = MacRoman.encode(string) else { return nil }
        self.init(bytes: bytes)
    }

    /// A string as the Toolbox keeps it: a length byte, then the bytes.
    /// Bytes past the end are ignored; a length longer than what follows
    /// takes what there is.
    public init(lengthPrefixed storage: some Collection<UInt8>) {
        guard let length = storage.first else {
            self.init()
            return
        }
        self.init(bytes: storage.dropFirst().prefix(Int(length)))
    }

    /// A C string's bytes up to its first zero (c2pstr), its first 255.
    public init(cString: some Sequence<UInt8>) {
        self.init(bytes: cString.prefix { $0 != 0 })
    }
}

public extension PascalString {

    var count: Int { bytes.count }

    var isEmpty: Bool { bytes.isEmpty }

    /// The length byte and the bytes.
    var lengthPrefixed: [UInt8] { [UInt8(bytes.count)] + bytes }

    /// The bytes and a terminating zero (p2cstr).
    var cString: [UInt8] { bytes + [0] }

    /// The text, read as MacRoman.
    var string: String { MacRoman.decode(bytes) }

    /// IdenticalString, as a Roman script compares: equal when they differ
    /// in case alone.
    func isEqualIgnoringCase(_ other: PascalString) -> Bool {
        count == other.count && (bytes == other.bytes || string.lowercased() == other.string.lowercased())
    }

    /// NumToString: the number's decimal digits, with a minus sign if it is
    /// negative.
    init(_ number: Int) {
        self.init(bytes: String(number).utf8)
    }

    /// StringToNum: the number the text starts with, after any spaces and
    /// a sign; the digits that follow until something else, wrapping at 32
    /// bits as the Toolbox's long does. No digits is zero.
    var integerValue: Int32 {
        var index = bytes.startIndex
        while index < bytes.endIndex, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
        var negative = false
        if index < bytes.endIndex, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") {
            negative = bytes[index] == UInt8(ascii: "-")
            index += 1
        }
        var value: Int32 = 0
        while index < bytes.endIndex, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) {
            value = value &* 10 &+ Int32(bytes[index] - UInt8(ascii: "0"))
            index += 1
        }
        return negative ? 0 &- value : value
    }
}

extension PascalString: ExpressibleByStringLiteral {

    /// A literal of MacRoman characters.
    public init(stringLiteral value: String) {
        guard let string = PascalString(value) else {
            preconditionFailure("\"\(value)\" has characters MacRoman doesn't")
        }
        self = string
    }
}

extension PascalString: CustomStringConvertible, CustomDebugStringConvertible {

    public var description: String { string }

    public var debugDescription: String { "PascalString(\(string.debugDescription))" }
}
