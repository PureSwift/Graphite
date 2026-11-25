import Testing
import GraphiteBase

@Suite struct PascalStringTests {

    @Test func storageForms() {
        let string: PascalString = "Café"
        #expect(string.bytes == [0x43, 0x61, 0x66, 0x8E])
        #expect(string.lengthPrefixed == [4, 0x43, 0x61, 0x66, 0x8E])
        #expect(string.cString == [0x43, 0x61, 0x66, 0x8E, 0])
        #expect(string.string == "Café")
        #expect(PascalString(lengthPrefixed: [3, 0x41, 0x42, 0x43, 0x44]).string == "ABC")
        #expect(PascalString(lengthPrefixed: [9, 0x41]).string == "A")
        #expect(PascalString(lengthPrefixed: []).isEmpty)
        #expect(PascalString(cString: [0x41, 0x42, 0, 0x43]).string == "AB")
    }

    @Test func atMost255Bytes() {
        let long = PascalString(bytes: Array(repeating: 0x41, count: 300))
        #expect(long.count == 255)
        #expect(long.lengthPrefixed.first == 255)
        var string = PascalString()
        string.bytes = Array(repeating: 0x42, count: 256)
        #expect(string.count == 255)
        #expect(PascalString(String(repeating: "x", count: 1000))?.count == 255)
    }

    @Test func textOutsideMacRoman() {
        // A literal is MacRoman by construction; other text may not be.
        let emoji = "😀"
        #expect(PascalString(emoji) == nil)
    }

    @Test func identicalStringIgnoresCase() {
        #expect(PascalString("Hello").isEqualIgnoringCase("hELLO"))
        #expect(PascalString("ÉCOLE").isEqualIgnoringCase("école"))
        #expect(!PascalString("Hello").isEqualIgnoringCase("Hello!"))
        #expect(!PascalString("Hello").isEqualIgnoringCase("Hellp"))
    }

    @Test func numToString() {
        #expect(PascalString(0).string == "0")
        #expect(PascalString(-1234).string == "-1234")
        #expect(PascalString(2147483647).string == "2147483647")
    }

    @Test func stringToNum() {
        #expect(PascalString("42").integerValue == 42)
        #expect(PascalString("  -17abc").integerValue == -17)
        #expect(PascalString("+8").integerValue == 8)
        #expect(PascalString("abc").integerValue == 0)
        #expect(PascalString("").integerValue == 0)
        #expect(PascalString("2147483648").integerValue == Int32.min)
    }
}

@Suite struct FourCharCodeTests {

    @Test func bytesAndValue() {
        let code: FourCharCode = "snd "
        #expect(code.rawValue == 0x736E_6420)
        #expect(code.bytes == [0x73, 0x6E, 0x64, 0x20])
        #expect(code.string == "snd ")
        #expect(code == FourCharCode(bytes: 0x73, 0x6E, 0x64, 0x20))
        #expect(code.debugDescription == "'snd '")
    }

    @Test func macRomanCharacters() {
        let code: FourCharCode = "©day"
        #expect(code.bytes == [0xA9, 0x64, 0x61, 0x79])
        #expect(FourCharCode(rawValue: 0xA964_6179).string == "©day")
    }

    @Test func onlyFourCharacters() {
        for text in ["abc", "abcde", "ab😀c"] {
            #expect(FourCharCode(text) == nil)
        }
    }
}
