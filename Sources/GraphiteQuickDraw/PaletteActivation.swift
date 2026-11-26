// Palettes on a device: giving a palette's entries places in its color
// table when the palette is activated, and changing the colors of the ones
// that asked to be animated.

import GraphiteBase

extension GraphicsDevice {

    /// How a palette entry gets its place in a device's table, by its
    /// usage: explicit first, then white and black, then animated.
    private enum Placement {
        case explicit, white, black, animated, nearest

        init(_ usage: PaletteUsage) {
            if usage.contains(.explicit) { self = .explicit }
            else if usage.contains(.white) { self = .white }
            else if usage.contains(.black) { self = .black }
            else if usage.contains(.animated) { self = .animated }
            else { self = .nearest }
        }
    }

    /// ActivatePalette: the palette's entries are given places in this
    /// device's table, recorded in its `deviceIndices`.
    ///
    /// - An explicit entry is the table's entry its red component names.
    /// - A white or black entry is the table's own.
    /// - An animated entry takes an entry of the table for itself, set to
    ///   its color and reserved so no other color is matched to it; from the
    ///   end of the table back, past its black, leaving protected and
    ///   reserved entries alone.
    /// - Any other entry, courteous, dithered or tolerant, is the nearest of
    ///   the table's colors, which it doesn't change.
    ///
    /// An entry with no place has nil. Nothing is placed on a direct device.
    public func activate(_ palette: Palette) {
        deactivate(palette)
        guard pixels.format.isIndexed else { return }
        let table = pixels.colorTable
        var indices: [Int?] = []
        for entry in palette.entries {
            switch Placement(entry.usage) {
            case .explicit:
                let index = Int(entry.color.red)
                indices.append(index < table.colors.count ? index : nil)
            case .white:
                indices.append(table.index(of: .white, excluding: pixels.reservedEntries))
            case .black:
                indices.append(table.index(of: .black, excluding: pixels.reservedEntries))
            case .animated:
                indices.append(allocateAnimatedEntry(color: entry.color))
            case .nearest:
                indices.append(table.index(of: entry.color, excluding: pixels.reservedEntries))
            }
        }
        palette.deviceIndices = indices
    }

    /// The palette gives its animated entries back: they are no longer
    /// reserved, and keep the colors they were last given.
    public func deactivate(_ palette: Palette) {
        for (entry, index) in zip(palette.entries, palette.deviceIndices) {
            if Placement(entry.usage) == .animated, let index { pixels.reservedEntries.remove(index) }
        }
        palette.deviceIndices = []
    }

    private func allocateAnimatedEntry(color: RGBColor) -> Int? {
        let count = pixels.colorTable.colors.count
        guard count > 2 else { return nil }
        for index in stride(from: count - 2, through: 1, by: -1)
        where !pixels.reservedEntries.contains(index) && !protectedEntries.contains(index) {
            pixels.colorTable.colors[index] = color
            pixels.colorTable.changed()
            pixels.reservedEntries.insert(index)
            return index
        }
        return nil
    }

    /// AnimateEntry: an animated entry of an active palette is given a new
    /// color, which shows at once in everything drawn with it. Parameter
    /// error for an entry that isn't animated, has no place, or isn't there.
    public func animateEntry(of palette: Palette, at entry: Int, to color: RGBColor) throws(MacError) {
        guard palette.entries.indices.contains(entry), palette.deviceIndices.indices.contains(entry),
              Placement(palette.entries[entry].usage) == .animated, let index = palette.deviceIndices[entry] else { throw .parameter }
        try palette.setColor(color, at: entry)
        pixels.colorTable.colors[index] = color
        pixels.colorTable.changed()
    }

    /// AnimatePalette: `count` colors of a table, from `sourceEntry`, are
    /// given to the palette's entries from `destinationEntry`, those that
    /// are animated; the others, and colors the table hasn't, are skipped.
    /// Parameter error for a first entry the palette hasn't.
    public func animateEntries(of palette: Palette, from table: ColorTable, sourceEntry: Int, destinationEntry: Int, count: Int) throws(MacError) {
        guard palette.entries.indices.contains(destinationEntry), sourceEntry >= 0, count >= 0 else { throw .parameter }
        for offset in 0 ..< count where destinationEntry + offset < palette.count && sourceEntry + offset < table.colors.count {
            try? animateEntry(of: palette, at: destinationEntry + offset, to: table.colors[sourceEntry + offset])
        }
    }
}
