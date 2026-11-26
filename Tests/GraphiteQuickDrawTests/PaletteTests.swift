import Testing
import GraphiteBase
import GraphiteQuickDraw

@Suite struct PaletteTests {

    private let red = RGBColor(red: 0xFFFF, green: 0, blue: 0)
    private let green = RGBColor(red: 0, green: 0xFFFF, blue: 0)
    private let blue = RGBColor(red: 0, green: 0, blue: 0xFFFF)

    @Test func entriesComeFromTheTableAndAreBlackPastIt() throws {
        let palette = Palette(count: 4, colors: ColorTable(colors: [red, green]), usage: .animated, tolerance: 7)
        #expect(palette.count == 4)
        #expect(try palette.color(at: 0) == red)
        #expect(try palette.color(at: 1) == green)
        #expect(try palette.color(at: 3) == .black)
        let usage = try palette.usage(at: 2)
        #expect(usage.usage == .animated && usage.tolerance == 7)
    }

    @Test func noTableMakesBlackCourteousEntries() throws {
        let palette = Palette(count: 2)
        #expect(try palette.color(at: 1) == .black)
        #expect(try palette.usage(at: 1).usage == [])
    }

    @Test func negativeCountIsEmpty() {
        #expect(Palette(count: -3).count == 0)
    }

    @Test func settingColorsAndUsage() throws {
        let palette = Palette(count: 3)
        try palette.setColor(blue, at: 2)
        try palette.setUsage([.explicit, .tolerant], tolerance: 40, at: 2)
        #expect(try palette.color(at: 2) == blue)
        #expect(try palette.usage(at: 2).usage == [.explicit, .tolerant])
        #expect(try palette.usage(at: 2).tolerance == 40)
        #expect(throws: MacError.parameter) { try palette.setColor(red, at: 3) }
        #expect(throws: MacError.parameter) { _ = try palette.color(at: -1) }
        #expect(throws: MacError.parameter) { try palette.setUsage([], tolerance: 0, at: 9) }
    }

    @Test func aPaletteIsAHandle() throws {
        let palette = Palette(count: 1)
        let alias = palette
        try alias.setColor(green, at: 0)
        #expect(try palette.color(at: 0) == green)
    }

    @Test func colorTableRoundTrip() {
        let palette = Palette(count: 3, colors: ColorTable(colors: [red, green, blue]))
        #expect(palette.colorTable.colors == [red, green, blue])
    }

    @Test func copyingEntries() throws {
        let source = Palette(count: 3, colors: ColorTable(colors: [red, green, blue]))
        let destination = Palette(count: 4)
        try destination.copy(from: source, sourceEntry: 1, destinationEntry: 2, length: 5)
        // Two fit in the destination from entry 2; the source has two from 1.
        #expect(destination.colorTable.colors == [.black, .black, green, blue])
        #expect(throws: MacError.parameter) { try destination.copy(from: source, sourceEntry: 3, destinationEntry: 0, length: 1) }
        #expect(throws: MacError.parameter) { try destination.copy(from: source, sourceEntry: 0, destinationEntry: 4, length: 1) }
    }

    @Test func copyingOverItself() throws {
        let palette = Palette(count: 4, colors: ColorTable(colors: [red, green, blue, .white]))
        try palette.copy(from: palette, sourceEntry: 0, destinationEntry: 1, length: 3)
        #expect(palette.colorTable.colors == [red, red, green, blue])
    }
}
