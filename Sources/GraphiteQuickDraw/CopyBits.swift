// CopyBits and its kin: pixels from one buffer to another, between any
// depths, scaled to fit the destination rectangle (each destination pixel
// takes the source pixel its center falls on), in a transfer mode, clipped
// to the destination port and a mask region. A 1-bit source is colorized:
// its set bits are the port's foreground color and its clear bits its
// background color.

import GraphiteBase

public extension Port {

    /// CopyBits into this port: `sourceRect` is in the source's
    /// coordinates, `destinationRect` and `mask` in the port's.
    func copyBits(from source: PixelBuffer, sourceRect: Rect, destinationRect: Rect, mode: TransferMode = .srcCopy, mask: Region? = nil) {
        guard let pixels else { return }
        var area = drawableRegion.intersection(Region(rect: destinationRect))
        if let mask { area = area.intersection(mask) }
        guard !area.isEmpty, !sourceRect.isEmpty, !destinationRect.isEmpty else { return }
        let isBitmap = source.format.depth == 1
        // The same pixels, unscaled, in the same format and table: copied as
        // stored.
        let raw = mode.base == .srcCopy && !isBitmap && source.format == pixels.format
            && (!source.format.isIndexed || source.colorTable.colors == pixels.colorTable.colors)
        for rect in area.rectangles {
            for v in rect.top ..< rect.bottom {
                let sourceV = scale(v, from: destinationRect.top, destinationRect.height, to: sourceRect.top, sourceRect.height)
                for h in rect.left ..< rect.right {
                    let sourceH = scale(h, from: destinationRect.left, destinationRect.width, to: sourceRect.left, sourceRect.width)
                    let from = Point(v: sourceV, h: sourceH), to = Point(v: v, h: h)
                    guard let value = source.value(at: from) else { continue }
                    if raw {
                        pixels.setValue(value, at: to)
                        continue
                    }
                    guard let existing = pixels.color(at: to) else { continue }
                    let color: RGBColor
                    if isBitmap {
                        color = mode.combine(isForeground: value != 0, drawn: foreColor, existing: existing,
                                             fore: foreColor, back: backColor, opColor: opColor)
                    } else {
                        color = combine(source.color(for: value), existing: existing, mode: mode)
                    }
                    pixels.setValue(pixels.value(for: color), at: to)
                }
            }
        }
    }

    /// CopyBits from this port's pixels into another buffer.
    func copyBits(from source: Port, sourceRect: Rect, destinationRect: Rect, mode: TransferMode = .srcCopy, mask: Region? = nil) {
        guard let buffer = source.pixels else { return }
        copyBits(from: buffer, sourceRect: sourceRect, destinationRect: destinationRect, mode: mode, mask: mask)
    }

    /// CopyMask: the source's pixels where the mask's are set; a mask of
    /// another depth than 1 counts any pixel that isn't white.
    func copyMask(from source: PixelBuffer, mask: PixelBuffer, sourceRect: Rect, maskRect: Rect, destinationRect: Rect) {
        guard let pixels else { return }
        let area = drawableRegion.intersection(Region(rect: destinationRect))
        guard !area.isEmpty, !sourceRect.isEmpty, !maskRect.isEmpty else { return }
        for rect in area.rectangles {
            for v in rect.top ..< rect.bottom {
                let sourceV = scale(v, from: destinationRect.top, destinationRect.height, to: sourceRect.top, sourceRect.height)
                let maskV = scale(v, from: destinationRect.top, destinationRect.height, to: maskRect.top, maskRect.height)
                for h in rect.left ..< rect.right {
                    let maskH = scale(h, from: destinationRect.left, destinationRect.width, to: maskRect.left, maskRect.width)
                    guard let maskValue = mask.value(at: Point(v: maskV, h: maskH)) else { continue }
                    let isSet = mask.format.depth == 1 ? maskValue != 0 : mask.color(for: maskValue) != .white
                    guard isSet else { continue }
                    let sourceH = scale(h, from: destinationRect.left, destinationRect.width, to: sourceRect.left, sourceRect.width)
                    guard let color = source.color(at: Point(v: sourceV, h: sourceH)) else { continue }
                    pixels.setColor(source.format.depth == 1 ? (color == .black ? foreColor : backColor) : color, at: Point(v: v, h: h))
                }
            }
        }
    }

    /// ScrollRect: the pixels in a rectangle moved by (dh, dv), and the part
    /// left behind erased. Returns that part, which the program redraws
    /// (the update region).
    @discardableResult
    func scroll(_ rect: Rect, dh: Int16, dv: Int16) -> Region {
        guard let pixels else { return Region() }
        let area = drawableRegion.intersection(Region(rect: rect))
        guard !area.isEmpty else { return Region() }
        let bounds = area.bounds
        let moved = area.offsetBy(dh: dh, dv: dv).intersection(area)
        // Read every pixel first, so that rows and columns overlapping the
        // move aren't read after they are written.
        var copies: [(Point, UInt32)] = []
        for target in moved.rectangles {
            for v in target.top ..< target.bottom {
                for h in target.left ..< target.right {
                    if let value = pixels.value(at: Point(v: v &- dv, h: h &- dh)) { copies.append((Point(v: v, h: h), value)) }
                }
            }
        }
        for (point, value) in copies { pixels.setValue(value, at: point) }
        let update = Region(rect: bounds).intersection(area).subtracting(moved)
        draw(update, pattern: backPattern, mode: .patCopy)
        return update
    }

    /// A color source pixel in a mode: copied, or combined with what is
    /// there. In the boolean modes a source pixel is foreground where it
    /// isn't the background color.
    private func combine(_ color: RGBColor, existing: RGBColor, mode: TransferMode) -> RGBColor {
        switch mode.base {
        case .srcCopy:
            return color
        case .notSrcCopy:
            return RGBColor(red: ~color.red, green: ~color.green, blue: ~color.blue)
        default:
            if mode.booleanOperation != nil {
                let isForeground = color != backColor
                return mode.combine(isForeground: isForeground, drawn: color, existing: existing, fore: foreColor, back: backColor, opColor: opColor)
            }
            return mode.combine(isForeground: true, drawn: color, existing: existing, fore: foreColor, back: backColor, opColor: opColor)
        }
    }
}

/// The source coordinate a destination pixel's center falls on.
private func scale(_ value: Int16, from origin: Int16, _ length: Int, to sourceOrigin: Int16, _ sourceLength: Int) -> Int16 {
    guard length != sourceLength else { return sourceOrigin &+ (value &- origin) }
    let offset = (2 * (Int(value) - Int(origin)) + 1) * sourceLength / (2 * length)
    return Int16(clamping: Int(sourceOrigin) + offset)
}
