// Mac OS Roman, the character set of a Roman-script Mac: ASCII below 0x80,
// accented letters, punctuation and symbols above, as Apple's mapping
// table gives them (with the euro sign at 0xDB, as since Mac OS 8.5, and
// the Apple logo at 0xF0, in Unicode's private use area).

public enum MacRoman {

    /// The text of MacRoman bytes. Every byte is a character.
    public static func decode(_ bytes: some Sequence<UInt8>) -> String {
        var scalars = String.UnicodeScalarView()
        for byte in bytes {
            scalars.append(scalar(byte))
        }
        return String(scalars)
    }

    /// The MacRoman bytes of the text, or nil when a character has none.
    /// Characters are compared as Unicode does, so a letter followed by a
    /// combining accent finds the accented letter's byte.
    public static func encode(_ string: String) -> [UInt8]? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(string.utf8.count)
        for character in string {
            // A carriage return and line feed are one character, whose
            // asciiValue is the line feed's.
            if character == "\r\n" {
                bytes.append(0x0D)
                bytes.append(0x0A)
            } else if let ascii = character.asciiValue {
                bytes.append(ascii)
            } else if let byte = upperHalf[character] {
                bytes.append(byte)
            } else {
                return nil
            }
        }
        return bytes
    }

    /// The character of one byte.
    public static func scalar(_ byte: UInt8) -> Unicode.Scalar {
        guard byte >= 0x80 else { return Unicode.Scalar(byte) }
        return Unicode.Scalar(table[Int(byte) - 0x80])!
    }

    /// The byte of one character, if MacRoman has it as one.
    public static func byte(_ character: Character) -> UInt8? {
        guard character != "\r\n" else { return nil }
        return character.asciiValue ?? upperHalf[character]
    }

    /// The Unicode scalars of bytes 0x80 to 0xFF.
    private static let table: [UInt16] = [
        0x00C4, 0x00C5, 0x00C7, 0x00C9, 0x00D1, 0x00D6, 0x00DC, 0x00E1,   // 0x80
        0x00E0, 0x00E2, 0x00E4, 0x00E3, 0x00E5, 0x00E7, 0x00E9, 0x00E8,   // 0x88
        0x00EA, 0x00EB, 0x00ED, 0x00EC, 0x00EE, 0x00EF, 0x00F1, 0x00F3,   // 0x90
        0x00F2, 0x00F4, 0x00F6, 0x00F5, 0x00FA, 0x00F9, 0x00FB, 0x00FC,   // 0x98
        0x2020, 0x00B0, 0x00A2, 0x00A3, 0x00A7, 0x2022, 0x00B6, 0x00DF,   // 0xA0
        0x00AE, 0x00A9, 0x2122, 0x00B4, 0x00A8, 0x2260, 0x00C6, 0x00D8,   // 0xA8
        0x221E, 0x00B1, 0x2264, 0x2265, 0x00A5, 0x00B5, 0x2202, 0x2211,   // 0xB0
        0x220F, 0x03C0, 0x222B, 0x00AA, 0x00BA, 0x03A9, 0x00E6, 0x00F8,   // 0xB8
        0x00BF, 0x00A1, 0x00AC, 0x221A, 0x0192, 0x2248, 0x2206, 0x00AB,   // 0xC0
        0x00BB, 0x2026, 0x00A0, 0x00C0, 0x00C3, 0x00D5, 0x0152, 0x0153,   // 0xC8
        0x2013, 0x2014, 0x201C, 0x201D, 0x2018, 0x2019, 0x00F7, 0x25CA,   // 0xD0
        0x00FF, 0x0178, 0x2044, 0x20AC, 0x2039, 0x203A, 0xFB01, 0xFB02,   // 0xD8
        0x2021, 0x00B7, 0x201A, 0x201E, 0x2030, 0x00C2, 0x00CA, 0x00C1,   // 0xE0
        0x00CB, 0x00C8, 0x00CD, 0x00CE, 0x00CF, 0x00CC, 0x00D3, 0x00D4,   // 0xE8
        0xF8FF, 0x00D2, 0x00DA, 0x00DB, 0x00D9, 0x0131, 0x02C6, 0x02DC,   // 0xF0
        0x00AF, 0x02D8, 0x02D9, 0x02DA, 0x00B8, 0x02DD, 0x02DB, 0x02C7,   // 0xF8
    ]

    /// Bytes 0x80 to 0xFF by character, with the characters Apple's table
    /// also maps to them: the ohm sign to omega, the micro sign's Greek
    /// twin to µ, the currency sign to the euro's byte that it once had.
    private static let upperHalf: [Character: UInt8] = {
        var bytes: [Character: UInt8] = [:]
        for (index, value) in table.enumerated() {
            bytes[Character(Unicode.Scalar(value)!)] = UInt8(0x80 + index)
        }
        bytes["\u{2126}"] = 0xBD
        bytes["\u{03BC}"] = 0xB5
        bytes["\u{00A4}"] = 0xDB
        return bytes
    }()
}
