import struct Foundation.Data
import Testing
import GraphiteBase
import GraphiteFiles

@Suite struct AppleDoubleBytesTests {

    private func file() -> [UInt8] {
        var double = AppleDouble()
        double.resourceFork = [1, 2, 3, 4]
        double.finderInfo = FinderInfo(type: "TEXT", creator: "ttxt", flags: 0x0400)
        return double.bytes
    }

    @Test func readsFromAnyBytes() throws {
        let bytes = file()
        let fromArray = try AppleDouble(bytes: bytes)
        #expect(fromArray.resourceFork == [1, 2, 3, 4])
        #expect(try AppleDouble(bytes: Data(bytes)) == fromArray)
        #expect(try AppleDouble(bytes: Data([7, 7, 7] + bytes)[3...]) == fromArray)
        #expect(try bytes.withUnsafeBytes { try AppleDouble(bytes: $0) } == fromArray)
    }

    @Test func recognisesAnyBytes() {
        let bytes = file()
        #expect(AppleDouble.isAppleDouble(bytes))
        #expect(AppleDouble.isAppleDouble(Data(bytes)))
        #expect(AppleDouble.isAppleDouble(Data([7, 7] + bytes)[2...]))
        #expect(!AppleDouble.isAppleDouble(Data([1, 2, 3, 4, 5])))
        #expect(!AppleDouble.isAppleDouble(Data()))
    }

    @Test func badBytesAreAParameterError() {
        #expect(throws: MacError.parameter) { try AppleDouble(bytes: Data([1, 2, 3, 4, 5, 6, 7, 8])) }
        #expect(throws: MacError.parameter) { try AppleDouble(bytes: Data(file().prefix(30))) }
    }
}
