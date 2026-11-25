// Four bytes read as one big-endian number: the OSType of resource types,
// file types and creators, Gestalt selectors, Apple Event classes and
// Carbon Event classes. Their bytes are MacRoman characters: 'snd ', 'TEXT',
// '©day'.

public struct FourCharCode: RawRepresentable, Hashable, Comparable, Sendable {

    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// The code of four bytes, the first the most significant.
    public init(bytes a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) {
        self.rawValue = UInt32(a) << 24 | UInt32(b) << 16 | UInt32(c) << 8 | UInt32(d)
    }

    /// The code of four MacRoman characters; nil for any other text.
    public init?(_ string: String) {
        guard let bytes = MacRoman.encode(string), bytes.count == 4 else { return nil }
        self.init(bytes: bytes[0], bytes[1], bytes[2], bytes[3])
    }

    /// The four bytes, as they're stored.
    public var bytes: [UInt8] {
        [UInt8(truncatingIfNeeded: rawValue >> 24), UInt8(truncatingIfNeeded: rawValue >> 16),
         UInt8(truncatingIfNeeded: rawValue >> 8), UInt8(truncatingIfNeeded: rawValue)]
    }

    /// The four characters, read as MacRoman.
    public var string: String { MacRoman.decode(bytes) }

    public static func < (lhs: FourCharCode, rhs: FourCharCode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension FourCharCode: ExpressibleByStringLiteral {

    /// Four MacRoman characters: `"snd "`.
    public init(stringLiteral value: String) {
        guard let code = FourCharCode(value) else {
            preconditionFailure("\"\(value)\" is not four MacRoman characters")
        }
        self = code
    }
}

extension FourCharCode: CustomStringConvertible, CustomDebugStringConvertible {

    public var description: String { string }

    public var debugDescription: String { "'\(string)'" }
}
