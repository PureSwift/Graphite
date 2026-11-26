// Colors and color tables: QuickDraw's RGBColor, 16 bits a component, and
// the tables indexed pixels look their colors up in, with the system's
// standard ones for each depth.

import GraphiteBase

/// QuickDraw's RGBColor: 16 bits a component.
public struct RGBColor: Hashable, Sendable {

    public var red: UInt16
    public var green: UInt16
    public var blue: UInt16

    public init(red: UInt16, green: UInt16, blue: UInt16) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Eight bits a component, each repeated in both bytes as QuickDraw
    /// widens them: 0xCC is 0xCCCC.
    public init(red8: UInt8, green8: UInt8, blue8: UInt8) {
        self.init(red: UInt16(red8) * 0x101, green: UInt16(green8) * 0x101, blue: UInt16(blue8) * 0x101)
    }

    public static var black: RGBColor { RGBColor(red: 0, green: 0, blue: 0) }
    public static var white: RGBColor { RGBColor(red: 0xFFFF, green: 0xFFFF, blue: 0xFFFF) }

    /// The old QuickDraw colors ForeColor and BackColor take, by their
    /// constants: blackColor (33), whiteColor (30), redColor (205),
    /// greenColor (341), blueColor (409), cyanColor (273), magentaColor
    /// (137), yellowColor (69).
    public init?(classic constant: Int32) {
        switch constant {
        case 33: self = .black
        case 30: self = .white
        case 205: self.init(red: 0xDD6B, green: 0x08C2, blue: 0x06A2)
        case 341: self.init(red: 0x0000, green: 0x8000, blue: 0x11B0)
        case 409: self.init(red: 0x0000, green: 0x0000, blue: 0xD400)
        case 273: self.init(red: 0x0241, green: 0xAB54, blue: 0xEAFF)
        case 137: self.init(red: 0xF2D7, green: 0x0856, blue: 0x84EC)
        case 69: self.init(red: 0xFC00, green: 0xF37D, blue: 0x052F)
        default: return nil
        }
    }

    /// The color's 8-bit components, as 32-bit pixels keep them.
    public var red8: UInt8 { UInt8(red >> 8) }
    public var green8: UInt8 { UInt8(green >> 8) }
    public var blue8: UInt8 { UInt8(blue >> 8) }

    /// How far apart two colors are, for finding the nearest in a table.
    func distance(to other: RGBColor) -> Int {
        let r = Int(red >> 8) - Int(other.red >> 8)
        let g = Int(green >> 8) - Int(other.green >> 8)
        let b = Int(blue >> 8) - Int(other.blue >> 8)
        return r * r + g * g + b * b
    }
}

/// A color table: the colors of an indexed pixel's values.
public struct ColorTable: Hashable, Sendable {

    /// ctSeed: changes when the colors do, so a cached inverse table knows
    /// to be made again.
    public var seed: Int32

    /// The colors, by pixel value.
    public var colors: [RGBColor]

    public init(seed: Int32 = 0, colors: [RGBColor]) {
        self.seed = seed
        self.colors = colors
    }

    /// The color of a pixel value; black past the table's end.
    public subscript(value: Int) -> RGBColor {
        value >= 0 && value < colors.count ? colors[value] : .black
    }

    /// Color2Index: the value whose color is nearest, an exact one first.
    public func index(of color: RGBColor) -> Int {
        if let exact = colors.firstIndex(of: color) { return exact }
        var best = 0
        var bestDistance = Int.max
        for (index, candidate) in colors.enumerated() {
            let distance = candidate.distance(to: color)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    /// The system's standard table for a depth of 1, 2, 4 or 8 bits ('clut'
    /// 1, 2, 4 and 8); nil for another.
    public static func standard(depth: Int) -> ColorTable? {
        switch depth {
        case 1: return ColorTable(seed: 1, colors: [.white, .black])
        case 2: return ColorTable(seed: 2, colors: [
            .white, RGBColor(red: 0xAAAA, green: 0xAAAA, blue: 0xAAAA), RGBColor(red: 0x5555, green: 0x5555, blue: 0x5555), .black,
        ])
        case 4: return standard4
        case 8: return standard8
        default: return nil
        }
    }

    /// The 16 colors of the system's 4-bit table.
    private static let standard4 = ColorTable(seed: 4, colors: [
        (0xFF, 0xFF, 0xFF), (0xFC, 0xF3, 0x05), (0xFF, 0x64, 0x02), (0xDD, 0x08, 0x06),
        (0xF2, 0x08, 0x84), (0x46, 0x00, 0xA5), (0x00, 0x00, 0xD4), (0x02, 0xAB, 0xEA),
        (0x1F, 0xB7, 0x14), (0x00, 0x64, 0x11), (0x56, 0x2C, 0x05), (0x90, 0x71, 0x3A),
        (0xC0, 0xC0, 0xC0), (0x80, 0x80, 0x80), (0x40, 0x40, 0x40), (0x00, 0x00, 0x00),
    ].map { RGBColor(red8: $0.0, green8: $0.1, blue8: $0.2) })

    /// The 256 colors of the system's 8-bit table: a 6×6×6 cube from white
    /// down without its black, then ramps of ten reds, greens, blues and
    /// grays, then black.
    private static let standard8: ColorTable = {
        let levels: [UInt8] = [0xFF, 0xCC, 0x99, 0x66, 0x33, 0x00]
        var colors: [RGBColor] = []
        for red in levels {
            for green in levels {
                for blue in levels where !(red == 0 && green == 0 && blue == 0) {
                    colors.append(RGBColor(red8: red, green8: green, blue8: blue))
                }
            }
        }
        let ramp: [UInt8] = [0xEE, 0xDD, 0xBB, 0xAA, 0x88, 0x77, 0x55, 0x44, 0x22, 0x11]
        colors += ramp.map { RGBColor(red8: $0, green8: 0, blue8: 0) }
        colors += ramp.map { RGBColor(red8: 0, green8: $0, blue8: 0) }
        colors += ramp.map { RGBColor(red8: 0, green8: 0, blue8: $0) }
        colors += ramp.map { RGBColor(red8: $0, green8: $0, blue8: $0) }
        colors.append(.black)
        return ColorTable(seed: 8, colors: colors)
    }()

    /// A 'clut' resource: ctSeed, ctFlags, ctSize (the count less one),
    /// then each entry's value and red, green and blue. A device table's
    /// entries are in order whatever their values say.
    public init(clut bytes: [UInt8]) throws(MacError) {
        var reader = BigEndianReader(bytes)
        do {
            seed = Int32(bitPattern: try reader.read(UInt32.self))
            let flags = try reader.read(UInt16.self)
            let count = Int(try reader.read(UInt16.self)) + 1
            var entries = [RGBColor](repeating: .black, count: count)
            for index in 0 ..< count {
                let value = Int(try reader.read(UInt16.self))
                let color = RGBColor(red: try reader.read(UInt16.self), green: try reader.read(UInt16.self), blue: try reader.read(UInt16.self))
                let slot = flags & 0x8000 != 0 ? index : value
                if slot < count { entries[slot] = color }
            }
            colors = entries
        } catch {
            throw .mapRead
        }
    }

    /// The table as a 'clut' resource.
    public var clut: [UInt8] {
        var writer = BigEndianWriter()
        writer.write(UInt32(bitPattern: seed))
        writer.write(UInt16(0))
        writer.write(UInt16(truncatingIfNeeded: colors.count - 1))
        for (value, color) in colors.enumerated() {
            writer.write(UInt16(value))
            writer.write(color.red)
            writer.write(color.green)
            writer.write(color.blue)
        }
        return writer.bytes
    }
}
