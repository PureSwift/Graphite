// The Palette Manager's palettes: the colors a window asks for, each with
// the way it wants to be given them. A palette is a handle in Carbon, so
// it is a class here; two references to it see the same changes.

import GraphiteBase

/// The usage an entry asks for (pmCourteous, pmDithered, pmTolerant,
/// pmAnimated, pmExplicit and the rest). Courteous, the default, is the
/// empty set.
public struct PaletteUsage: OptionSet, Hashable, Sendable {

    public var rawValue: Int16

    public init(rawValue: Int16) {
        self.rawValue = rawValue
    }

    public static var dithered: PaletteUsage { PaletteUsage(rawValue: 0x0001) }
    public static var tolerant: PaletteUsage { PaletteUsage(rawValue: 0x0002) }
    public static var animated: PaletteUsage { PaletteUsage(rawValue: 0x0004) }
    public static var explicit: PaletteUsage { PaletteUsage(rawValue: 0x0008) }
    public static var white: PaletteUsage { PaletteUsage(rawValue: 0x0010) }
    public static var black: PaletteUsage { PaletteUsage(rawValue: 0x0020) }
}

/// One color of a palette: the color, how it is asked for, and how far a
/// tolerant request may be from it (a color's component units).
public struct PaletteEntry: Hashable, Sendable {

    public var color: RGBColor
    public var usage: PaletteUsage
    public var tolerance: Int16

    public init(color: RGBColor = .black, usage: PaletteUsage = [], tolerance: Int16 = 0) {
        self.color = color
        self.usage = usage
        self.tolerance = tolerance
    }
}

public final class Palette {

    public private(set) var entries: [PaletteEntry]

    /// The entry of a device's table each of the palette's entries is
    /// given while the palette is active on it; nil for one that has none.
    /// Empty while it isn't active.
    public internal(set) var deviceIndices: [Int?] = []

    /// NewPalette: `count` entries, their colors from a table's where it has
    /// them (CTab2Palette) and black where it hasn't, all with one usage and
    /// tolerance.
    public init(count: Int, colors: ColorTable? = nil, usage: PaletteUsage = [], tolerance: Int16 = 0) {
        entries = (0 ..< max(0, min(count, Int(Int16.max)))).map { index in
            PaletteEntry(color: colors?.colors.indices.contains(index) == true ? colors![index] : .black,
                         usage: usage, tolerance: tolerance)
        }
    }

    public var count: Int { entries.count }

    /// Palette2CTab: the palette's colors as a table.
    public var colorTable: ColorTable {
        ColorTable(colors: entries.map(\.color))
    }

    /// GetEntryColor.
    public func color(at index: Int) throws(MacError) -> RGBColor {
        guard entries.indices.contains(index) else { throw .parameter }
        return entries[index].color
    }

    /// SetEntryColor.
    public func setColor(_ color: RGBColor, at index: Int) throws(MacError) {
        guard entries.indices.contains(index) else { throw .parameter }
        entries[index].color = color
    }

    /// GetEntryUsage.
    public func usage(at index: Int) throws(MacError) -> (usage: PaletteUsage, tolerance: Int16) {
        guard entries.indices.contains(index) else { throw .parameter }
        return (entries[index].usage, entries[index].tolerance)
    }

    /// SetEntryUsage.
    public func setUsage(_ usage: PaletteUsage, tolerance: Int16, at index: Int) throws(MacError) {
        guard entries.indices.contains(index) else { throw .parameter }
        entries[index].usage = usage
        entries[index].tolerance = tolerance
    }

    /// CopyPalette: entries of another palette copied over this one's from
    /// `destinationEntry`, as many as `length` and both palettes have.
    public func copy(from source: Palette, sourceEntry: Int, destinationEntry: Int, length: Int) throws(MacError) {
        guard source.entries.indices.contains(sourceEntry), entries.indices.contains(destinationEntry), length >= 0 else {
            throw .parameter
        }
        let amount = min(length, source.count - sourceEntry, count - destinationEntry)
        // Taken first, as a palette may be copied over itself.
        let moved = Array(source.entries[sourceEntry ..< sourceEntry + amount])
        entries.replaceSubrange(destinationEntry ..< destinationEntry + amount, with: moved)
    }
}
