import Testing
import GraphiteBase

@Suite struct MacRomanTests {

    @Test func everyByteRoundTrips() throws {
        for byte in UInt8.min ... UInt8.max where byte != 0x0D {
            let text = MacRoman.decode([byte])
            #expect(text.unicodeScalars.count == 1)
            #expect(MacRoman.encode(text) == [byte], "byte \(byte)")
        }
        // A carriage return alone, and one before a line feed.
        #expect(MacRoman.encode(MacRoman.decode([0x0D])) == [0x0D])
        #expect(MacRoman.encode(MacRoman.decode([0x0D, 0x0A])) == [0x0D, 0x0A])
        let all = (UInt8.min ... UInt8.max).map { $0 }
        #expect(MacRoman.encode(MacRoman.decode(all)) == all)
    }

    @Test func knownCharacters() {
        #expect(MacRoman.decode([0x80]) == "Ä")
        #expect(MacRoman.decode([0xA5]) == "•")
        #expect(MacRoman.decode([0xA9]) == "©")
        #expect(MacRoman.decode([0xCA]) == "\u{00A0}")
        #expect(MacRoman.decode([0xDB]) == "€")
        #expect(MacRoman.decode([0xF0]) == "\u{F8FF}")
        #expect(MacRoman.decode([0xFF]) == "ˇ")
        #expect(MacRoman.decode(Array("Hello".utf8)) == "Hello")
    }

    @Test func encodingFindsEquivalentCharacters() {
        #expect(MacRoman.encode("e\u{0301}") == [0x8E])     // é, decomposed
        #expect(MacRoman.encode("\u{2126}") == [0xBD])      // the ohm sign
        #expect(MacRoman.encode("\u{03BC}") == [0xB5])      // Greek mu
        #expect(MacRoman.encode("Ω≈ç") == [0xBD, 0xC5, 0x8D])
    }

    @Test func unmappableTextIsNil() {
        #expect(MacRoman.encode("日本") == nil)
        #expect(MacRoman.encode("a😀") == nil)
        #expect(MacRoman.byte("😀") == nil)
        #expect(MacRoman.byte("ü") == 0x9F)
    }
}
