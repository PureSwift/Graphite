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
}
