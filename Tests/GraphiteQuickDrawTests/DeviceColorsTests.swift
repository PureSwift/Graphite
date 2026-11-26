import Testing
import GraphiteBase
import GraphiteQuickDraw

@Suite struct DeviceColorsTests {

    private func indexedDevice() -> GraphicsDevice {
        let bounds = Rect(top: 0, left: 0, bottom: 4, right: 4)
        let pixels = PixelBuffer(bounds: bounds, format: .indexed(depth: 8), colorTable: ColorTable.standard(depth: 8))
        return GraphicsDevice(bounds: bounds, pixels: pixels, isScreen: true)
    }

    private let orange = RGBColor(red: 0xFFFF, green: 0x8000, blue: 0)

    @Test func changedMovesTheSeed() {
        var table = ColorTable(seed: 5, colors: [.black])
        table.changed()
        #expect(table.seed == 6)
        var last = ColorTable(seed: .max, colors: [])
        last.changed()
        #expect(last.seed == .min)
    }

    @Test func index2ColorReadsTheDevicesTable() {
        let device = indexedDevice()
        #expect(device.color(forIndex: 0) == .white)
        #expect(device.color(forIndex: 255) == .black)
        #expect(device.color(forIndex: 256) == nil)
        #expect(device.color(forIndex: -1) == nil)
    }

    @Test func index2ColorOnADirectDeviceIsNil() {
        #expect(GraphicsDevice.screen(width: 4, height: 4, depth: 32).color(forIndex: 0) == nil)
    }

    @Test func setEntriesWritesAndBumpsTheSeed() throws {
        let device = indexedDevice()
        let seed = device.pixels.colorTable.seed
        try device.setEntries(from: 10, colors: [orange, .black])
        #expect(device.color(forIndex: 10) == orange)
        #expect(device.color(forIndex: 11) == .black)
        #expect(device.pixels.colorTable.seed != seed)
    }

    @Test func setEntriesStopsAtTheTablesEnd() throws {
        let device = indexedDevice()
        try device.setEntries(from: 255, colors: [orange, orange, orange])
        #expect(device.color(forIndex: 255) == orange)
        #expect(device.pixels.colorTable.colors.count == 256)
        #expect(throws: MacError.parameter) { try device.setEntries(from: 256, colors: [orange]) }
        #expect(throws: MacError.parameter) { try device.setEntries(from: -1, colors: [orange]) }
    }

    @Test func setEntriesOnADirectDeviceDoesNothing() throws {
        let device = GraphicsDevice.screen(width: 4, height: 4, depth: 32)
        try device.setEntries(from: 0, colors: [orange])
    }

    @Test func restoringBringsBackTheStandardColors() throws {
        let device = indexedDevice()
        try device.setEntries(from: 0, colors: [orange])
        let seed = device.pixels.colorTable.seed
        device.restoreColorTable()
        #expect(device.color(forIndex: 0) == .white)
        #expect(device.pixels.colorTable.colors == ColorTable.standard(depth: 8)?.colors)
        #expect(device.pixels.colorTable.seed != seed)
    }

    // MARK: Reserved and protected entries

    @Test func matchingSkipsExcludedEntries() {
        let table = ColorTable(colors: [.white, RGBColor(red: 0xFF00, green: 0xFF00, blue: 0xFF00), .black])
        #expect(table.index(of: .white) == 0)
        #expect(table.index(of: .white, excluding: [0]) == 1)
        #expect(table.index(of: .white, excluding: [0, 1]) == 2)
        #expect(table.index(of: .white, excluding: [0, 1, 2]) == 0)
    }

    @Test func reservedEntriesAreNotMatchedInDrawing() throws {
        let device = indexedDevice()
        #expect(device.pixels.value(for: .white) == 0)
        try device.reserveEntry(0, true)
        #expect(device.pixels.reservedEntries == [0])
        let value = device.pixels.value(for: .white)
        #expect(value != 0)
        #expect(device.pixels.color(for: value).red8 >= 0xEE)
        try device.reserveEntry(0, false)
        #expect(device.pixels.value(for: .white) == 0)
        // A reserved entry still holds its color, which SetEntries can change.
        try device.reserveEntry(5, true)
        try device.setEntries(from: 5, colors: [orange])
        #expect(device.color(forIndex: 5) == orange)
    }

    @Test func protectedEntriesKeepTheirColors() throws {
        let device = indexedDevice()
        let before = device.color(forIndex: 10)
        try device.protectEntry(10, true)
        try device.setEntries(from: 9, colors: [orange, orange, orange])
        #expect(device.color(forIndex: 9) == orange)
        #expect(device.color(forIndex: 10) == before)
        #expect(device.color(forIndex: 11) == orange)
        try device.protectEntry(10, false)
        try device.setEntries(from: 10, colors: [orange])
        #expect(device.color(forIndex: 10) == orange)
    }

    @Test func badEntriesAreParameterErrors() {
        let device = indexedDevice()
        #expect(throws: MacError.parameter) { try device.reserveEntry(256, true) }
        #expect(throws: MacError.parameter) { try device.reserveEntry(-1, true) }
        #expect(throws: MacError.parameter) { try device.protectEntry(256, true) }
        #expect(throws: MacError.parameter) { try device.protectEntry(-1, false) }
    }

    @Test func directDevicesIgnoreTheFlags() throws {
        let device = GraphicsDevice.screen(width: 4, height: 4, depth: 32)
        try device.reserveEntry(0, true)
        try device.protectEntry(0, true)
        try device.reserveEntry(9999, true)
        #expect(device.pixels.reservedEntries.isEmpty && device.protectedEntries.isEmpty)
    }

    @Test func restoringClearsTheFlags() throws {
        let device = indexedDevice()
        try device.reserveEntry(3, true)
        try device.protectEntry(4, true)
        device.restoreColorTable()
        #expect(device.pixels.reservedEntries.isEmpty)
        #expect(device.protectedEntries.isEmpty)
    }
}
