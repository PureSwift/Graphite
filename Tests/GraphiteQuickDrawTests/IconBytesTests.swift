import struct Foundation.Data
import Testing
import GraphiteBase
import GraphiteQuickDraw

@Suite struct IconBytesTests {

    /// An 'icns' file with one 'ICN#' member, every pixel black and shown.
    private let file: [UInt8] = {
        func be(_ value: UInt32) -> [UInt8] {
            [UInt8(value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
        }
        let member = [UInt8](repeating: 0xFF, count: 256)
        return be(FourCharCode("icns").rawValue) + be(UInt32(16 + member.count)) + be(FourCharCode("ICN#").rawValue)
            + be(UInt32(8 + member.count)) + member
    }()

    @Test func familiesReadFromAnyBytes() throws {
        #expect(try IconFamily(icns: file).sizes == [32])
        #expect(try IconFamily(icns: Data(file)).sizes == [32])
        #expect(try file.withUnsafeBytes { try IconFamily(icns: $0) }.sizes == [32])
    }

    @Test func aSliceOfDataIsReadFromItsOwnStart() throws {
        let padded = Data([9, 9, 9, 9] + file)
        let family = try IconFamily(icns: padded[4...])
        #expect(family.sizes == [32])
        #expect(family.image(size: 32)?.value(column: 0, row: 0) == 0xFF00_0000)
    }

    @Test func badBytesAreAParameterError() {
        #expect(throws: MacError.parameter) { try IconFamily(icns: Data([0, 1, 2, 3])) }
        #expect(throws: MacError.parameter) { try IconFamily(icns: Data()) }
    }
}
