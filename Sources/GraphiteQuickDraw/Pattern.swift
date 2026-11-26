// QuickDraw's patterns, eight rows of eight bits that repeat across a port
// from its origin, and the transfer modes that say how what is drawn meets
// what is there.

import GraphiteBase

/// Eight rows of eight bits, the high bit leftmost: a set bit is the
/// foreground color.
public struct Pattern: Hashable, Sendable {

    public var rows: [UInt8]

    /// The first eight bytes; zeros after fewer.
    public init(_ rows: some Sequence<UInt8>) {
        var all = Array(rows.prefix(8))
        if all.count < 8 { all += [UInt8](repeating: 0, count: 8 - all.count) }
        self.rows = all
    }

    public static var white: Pattern { Pattern([UInt8](repeating: 0x00, count: 8)) }
    public static var black: Pattern { Pattern([UInt8](repeating: 0xFF, count: 8)) }
    public static var gray: Pattern { Pattern([0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55]) }
    public static var lightGray: Pattern { Pattern([0x88, 0x22, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22]) }
    public static var darkGray: Pattern { Pattern([0x77, 0xDD, 0x77, 0xDD, 0x77, 0xDD, 0x77, 0xDD]) }

    /// Whether the pattern is set at a point of a port's plane: it repeats
    /// every eight pixels each way.
    public func isSet(at point: Point) -> Bool {
        let row = rows[Int(point.v & 7)]
        return row & (0x80 >> UInt8(point.h & 7)) != 0
    }

    /// Every bit set or none: drawing with it is a solid color.
    public var isSolid: Bool { rows.allSatisfy { $0 == rows[0] } && (rows[0] == 0 || rows[0] == 0xFF) }
}

/// How drawn pixels combine with those there: a source mode (CopyBits,
/// text), a pattern mode (shapes and lines), or an arithmetic one.
public struct TransferMode: RawRepresentable, Hashable, Sendable {

    public var rawValue: Int16

    public init(rawValue: Int16) {
        self.rawValue = rawValue
    }

    public static var srcCopy: TransferMode { TransferMode(rawValue: 0) }
    public static var srcOr: TransferMode { TransferMode(rawValue: 1) }
    public static var srcXor: TransferMode { TransferMode(rawValue: 2) }
    public static var srcBic: TransferMode { TransferMode(rawValue: 3) }
    public static var notSrcCopy: TransferMode { TransferMode(rawValue: 4) }
    public static var notSrcOr: TransferMode { TransferMode(rawValue: 5) }
    public static var notSrcXor: TransferMode { TransferMode(rawValue: 6) }
    public static var notSrcBic: TransferMode { TransferMode(rawValue: 7) }
    public static var patCopy: TransferMode { TransferMode(rawValue: 8) }
    public static var patOr: TransferMode { TransferMode(rawValue: 9) }
    public static var patXor: TransferMode { TransferMode(rawValue: 10) }
    public static var patBic: TransferMode { TransferMode(rawValue: 11) }
    public static var notPatCopy: TransferMode { TransferMode(rawValue: 12) }
    public static var notPatOr: TransferMode { TransferMode(rawValue: 13) }
    public static var notPatXor: TransferMode { TransferMode(rawValue: 14) }
    public static var notPatBic: TransferMode { TransferMode(rawValue: 15) }
    public static var grayishTextOr: TransferMode { TransferMode(rawValue: 49) }
    public static var hilite: TransferMode { TransferMode(rawValue: 50) }
    public static var blend: TransferMode { TransferMode(rawValue: 32) }
    public static var addPin: TransferMode { TransferMode(rawValue: 33) }
    public static var addOver: TransferMode { TransferMode(rawValue: 34) }
    public static var subPin: TransferMode { TransferMode(rawValue: 35) }
    public static var transparent: TransferMode { TransferMode(rawValue: 36) }
    public static var addMax: TransferMode { TransferMode(rawValue: 37) }
    public static var subOver: TransferMode { TransferMode(rawValue: 38) }
    public static var addMin: TransferMode { TransferMode(rawValue: 39) }
    /// ditherCopy: srcCopy with dithering, which a mode's bit 64 asks for.
    public static var ditherCopy: TransferMode { TransferMode(rawValue: 64) }

    /// The mode without its dither bit.
    public var base: TransferMode { TransferMode(rawValue: rawValue & ~64) }

    /// One of the eight boolean modes, as their source or pattern form.
    public var booleanOperation: Int16? {
        let mode = base.rawValue
        return mode < 16 ? mode & 7 : nil
    }

    /// Whether the mode inverts what it draws before combining it.
    public var invertsSource: Bool { (booleanOperation ?? 0) >= 4 }

    /// Combines a drawn color with the one there, for every mode but hilite,
    /// which needs the port's highlight color, and grayishTextOr, which is
    /// srcOr here. `isForeground` is whether the source or pattern bit there
    /// is set; `fore`, `back` and `opColor` are the port's.
    public func combine(isForeground: Bool, drawn: RGBColor, existing: RGBColor,
                        fore: RGBColor, back: RGBColor, opColor: RGBColor = RGBColor(red: 0x7FFF, green: 0x7FFF, blue: 0x7FFF)) -> RGBColor {
        if let operation = booleanOperation {
            let set = operation >= 4 ? !isForeground : isForeground
            switch operation & 3 {
            case 0: return set ? drawn : back                           // copy
            case 1: return set ? drawn : existing                       // or
            case 2:                                                     // xor
                guard set else { return existing }
                return RGBColor(red: ~existing.red, green: ~existing.green, blue: ~existing.blue)
            default: return set ? back : existing                       // bic
            }
        }
        func each(_ body: (Int, Int, Int) -> Int) -> RGBColor {
            RGBColor(
                red: UInt16(clamping: body(Int(drawn.red), Int(existing.red), Int(opColor.red))),
                green: UInt16(clamping: body(Int(drawn.green), Int(existing.green), Int(opColor.green))),
                blue: UInt16(clamping: body(Int(drawn.blue), Int(existing.blue), Int(opColor.blue)))
            )
        }
        switch base {
        case .blend: return each { source, destination, weight in (source * weight + destination * (0xFFFF - weight)) / 0xFFFF }
        case .addPin: return each { source, destination, pin in min(source + destination, pin) }
        case .addOver: return each { source, destination, _ in (source + destination) & 0xFFFF }
        case .subPin: return each { source, destination, pin in max(destination - source, 0xFFFF - pin) }
        case .subOver: return each { source, destination, _ in (destination - source) & 0xFFFF }
        case .addMax: return each { source, destination, _ in max(source, destination) }
        case .addMin: return each { source, destination, _ in min(source, destination) }
        case .transparent: return drawn == back ? existing : drawn
        case .grayishTextOr: return isForeground ? drawn : existing
        default: return isForeground ? drawn : existing
        }
    }
}
