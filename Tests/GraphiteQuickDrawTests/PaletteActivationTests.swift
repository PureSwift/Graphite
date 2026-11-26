import Testing
import GraphiteBase
import GraphiteQuickDraw

@Suite struct PaletteActivationTests {

    private func indexedDevice() -> GraphicsDevice {
        let bounds = Rect(top: 0, left: 0, bottom: 4, right: 4)
        let pixels = PixelBuffer(bounds: bounds, format: .indexed(depth: 8), colorTable: ColorTable.standard(depth: 8))
        return GraphicsDevice(bounds: bounds, pixels: pixels, isScreen: true)
    }

    private let orange = RGBColor(red: 0xFFFF, green: 0x8000, blue: 0)
    private let purple = RGBColor(red: 0x8000, green: 0, blue: 0x8000)
    private let teal = RGBColor(red: 0, green: 0x8000, blue: 0x8000)

    private func palette(_ usages: [PaletteUsage], colors: [RGBColor]) throws -> Palette {
        let palette = Palette(count: usages.count)
        for (index, usage) in usages.enumerated() {
            try palette.setColor(colors[index], at: index)
            try palette.setUsage(usage, tolerance: 0, at: index)
        }
        return palette
    }

    @Test func animatedEntriesTakeReservedPlacesFromTheEnd() throws {
        let device = indexedDevice()
        let palette = try palette([.animated, .animated], colors: [orange, purple])
        device.activate(palette)
        // Past the black at 255, back from 254.
        #expect(palette.deviceIndices == [254, 253])
        #expect(device.color(forIndex: 254) == orange)
        #expect(device.color(forIndex: 253) == purple)
        #expect(device.pixels.reservedEntries == [254, 253])
        // Drawing in the color doesn't find the animated entries.
        #expect(device.pixels.value(for: orange) != 254)
    }

    @Test func animatingChangesTheDeviceAndThePalette() throws {
        let device = indexedDevice()
        let palette = try palette([.animated, []], colors: [orange, teal])
        device.activate(palette)
        let index = try #require(palette.deviceIndices[0])
        let seed = device.pixels.colorTable.seed
        try device.animateEntry(of: palette, at: 0, to: purple)
        #expect(device.color(forIndex: index) == purple)
        #expect(try palette.color(at: 0) == purple)
        #expect(device.pixels.colorTable.seed != seed)
        // An entry that isn't animated, or isn't there, can't be.
        #expect(throws: MacError.parameter) { try device.animateEntry(of: palette, at: 1, to: purple) }
        #expect(throws: MacError.parameter) { try device.animateEntry(of: palette, at: 2, to: purple) }
    }

    @Test func aPaletteThatIsntActiveCantAnimate() throws {
        let device = indexedDevice()
        let palette = try palette([.animated], colors: [orange])
        #expect(throws: MacError.parameter) { try device.animateEntry(of: palette, at: 0, to: purple) }
        device.activate(palette)
        device.deactivate(palette)
        #expect(throws: MacError.parameter) { try device.animateEntry(of: palette, at: 0, to: purple) }
    }

    @Test func animatingFromATable() throws {
        let device = indexedDevice()
        let palette = try palette([.animated, [], .animated], colors: [orange, teal, purple])
        device.activate(palette)
        let source = ColorTable(colors: [.white, .black, RGBColor(red: 0x1111, green: 0x2222, blue: 0x3333)])
        try device.animateEntries(of: palette, from: source, sourceEntry: 0, destinationEntry: 0, count: 3)
        #expect(try palette.color(at: 0) == .white)
        #expect(try palette.color(at: 1) == teal)
        #expect(try palette.color(at: 2) == source.colors[2])
        #expect(device.color(forIndex: try #require(palette.deviceIndices[2])) == source.colors[2])
        // Colors the table hasn't are skipped; a first entry the palette hasn't is an error.
        try device.animateEntries(of: palette, from: source, sourceEntry: 2, destinationEntry: 2, count: 5)
        #expect(throws: MacError.parameter) { try device.animateEntries(of: palette, from: source, sourceEntry: 0, destinationEntry: 3, count: 1) }
    }

    @Test func explicitWhiteBlackAndNearestEntries() throws {
        let device = indexedDevice()
        let nearOrange = RGBColor(red: 0xFFFF, green: 0x8800, blue: 0x0200)
        let palette = try palette(
            [.explicit, .explicit, .white, .black, [], .tolerant],
            colors: [RGBColor(red: 7, green: 0, blue: 0), RGBColor(red: 300, green: 0, blue: 0), .black, .white, nearOrange, nearOrange])
        let before = device.pixels.colorTable
        device.activate(palette)
        let expectedNearest = before.index(of: nearOrange)
        #expect(palette.deviceIndices == [7, nil, 0, 255, expectedNearest, expectedNearest])
        // Placing these changes nothing.
        #expect(device.pixels.colorTable == before)
        #expect(device.pixels.reservedEntries.isEmpty)
    }

    @Test func allocationLeavesReservedAndProtectedEntriesAlone() throws {
        let device = indexedDevice()
        try device.reserveEntry(254, true)
        try device.protectEntry(253, true)
        let palette = try palette([.animated], colors: [orange])
        device.activate(palette)
        #expect(palette.deviceIndices == [252])
        #expect(device.color(forIndex: 253) == ColorTable.standard(depth: 8)?.colors[253])
    }

    @Test func entriesRunOutAndHaveNoPlace() throws {
        let device = indexedDevice()
        for index in 1 ... 254 where index != 100 { try device.reserveEntry(index, true) }
        let palette = try palette([.animated, .animated], colors: [orange, purple])
        device.activate(palette)
        #expect(palette.deviceIndices == [100, nil])
        let small = GraphicsDevice(bounds: Rect(top: 0, left: 0, bottom: 2, right: 2),
                                   pixels: PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: 2, right: 2), format: .indexed(depth: 1)),
                                   isScreen: false)
        let one = try self.palette([.animated], colors: [orange])
        small.activate(one)
        #expect(one.deviceIndices == [nil])
    }

    @Test func deactivatingGivesTheEntriesBack() throws {
        let device = indexedDevice()
        let palette = try palette([.animated], colors: [orange])
        device.activate(palette)
        #expect(device.pixels.reservedEntries == [254])
        device.deactivate(palette)
        #expect(device.pixels.reservedEntries.isEmpty)
        #expect(palette.deviceIndices.isEmpty)
        // The color stays where it was put; activating again places it afresh.
        #expect(device.color(forIndex: 254) == orange)
        device.activate(palette)
        device.activate(palette)
        #expect(palette.deviceIndices == [254])
        #expect(device.pixels.reservedEntries == [254])
    }

    @Test func nothingIsPlacedOnADirectDevice() throws {
        let device = GraphicsDevice.screen(width: 4, height: 4, depth: 32)
        let palette = try palette([.animated, []], colors: [orange, teal])
        device.activate(palette)
        #expect(palette.deviceIndices.isEmpty)
        #expect(throws: MacError.parameter) { try device.animateEntry(of: palette, at: 0, to: purple) }
    }
}
