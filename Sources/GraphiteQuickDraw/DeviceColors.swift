// The color table a device's indexed pixels look up: Index2Color,
// SetEntries, ReserveEntry, ProtectEntry and RestoreDeviceClut, and
// CTabChanged for any table.

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
    /// as many as the table has room for, except the protected entries,
    /// which keep their colors. Does nothing on a direct device.
    public func setEntries(from start: Int, colors: [RGBColor]) throws(MacError) {
        guard pixels.format.isIndexed else { return }
        guard start >= 0, start < pixels.colorTable.colors.count else { throw .parameter }
        for (offset, color) in colors.enumerated() where start + offset < pixels.colorTable.colors.count {
            if !protectedEntries.contains(start + offset) { pixels.colorTable.colors[start + offset] = color }
        }
        pixels.colorTable.changed()
    }

    /// ReserveEntry: a reserved entry is one no color is matched to, as
    /// Color2Index and drawing in a color find the nearest; a program keeps
    /// it to set as it likes. Parameter error for an entry the table hasn't;
    /// does nothing on a direct device.
    public func reserveEntry(_ index: Int, _ reserve: Bool) throws(MacError) {
        guard pixels.format.isIndexed else { return }
        guard index >= 0, index < pixels.colorTable.colors.count else { throw .parameter }
        if reserve { pixels.reservedEntries.insert(index) } else { pixels.reservedEntries.remove(index) }
    }

    /// ProtectEntry: a protected entry keeps its color through SetEntries.
    /// Parameter error for an entry the table hasn't; does nothing on a
    /// direct device.
    public func protectEntry(_ index: Int, _ protect: Bool) throws(MacError) {
        guard pixels.format.isIndexed else { return }
        guard index >= 0, index < pixels.colorTable.colors.count else { throw .parameter }
        if protect { protectedEntries.insert(index) } else { protectedEntries.remove(index) }
    }

    /// RestoreDeviceClut: the system's standard table for the device's
    /// depth again, with no entry reserved or protected. Does nothing on a
    /// direct device.
    public func restoreColorTable() {
        guard pixels.format.isIndexed, var standard = ColorTable.standard(depth: depth) else { return }
        standard.seed = pixels.colorTable.seed
        standard.changed()
        pixels.colorTable = standard
        pixels.reservedEntries = []
        protectedEntries = []
    }
}
