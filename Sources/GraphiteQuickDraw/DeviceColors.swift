// The color table a device's indexed pixels look up: Index2Color,
// SetEntries and RestoreDeviceClut, and CTabChanged for any table.

import GraphiteBase

extension ColorTable {

    /// CTabChanged: a program changed the colors, so anything cached from
    /// them is stale.
    public mutating func changed() {
        seed &+= 1
    }
}

extension GraphicsDevice {

    /// Index2Color: the color of a pixel value on this device. Nil on a
    /// direct device, whose pixels hold colors, not indexes.
    public func color(forIndex index: Int) -> RGBColor? {
        guard pixels.format.isIndexed, index >= 0, index < pixels.colorTable.colors.count else { return nil }
        return pixels.colorTable.colors[index]
    }

    /// SetEntries: colors written into the device's table from `start`,
    /// as many as the table has room for. Does nothing on a direct device.
    public func setEntries(from start: Int, colors: [RGBColor]) throws(MacError) {
        guard pixels.format.isIndexed else { return }
        guard start >= 0, start < pixels.colorTable.colors.count else { throw .parameter }
        for (offset, color) in colors.enumerated() where start + offset < pixels.colorTable.colors.count {
            pixels.colorTable.colors[start + offset] = color
        }
        pixels.colorTable.changed()
    }

    /// RestoreDeviceClut: the system's standard table for the device's
    /// depth again. Does nothing on a direct device.
    public func restoreColorTable() {
        guard pixels.format.isIndexed, var standard = ColorTable.standard(depth: depth) else { return }
        standard.seed = pixels.colorTable.seed
        standard.changed()
        pixels.colorTable = standard
    }
}
