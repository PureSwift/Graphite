// Drawing in a port, as QuickDraw draws: every shape becomes the region it
// covers, which is drawn with a pattern and a transfer mode, clipped to the
// port's rectangle, clip region and visible region. A pattern's bits are
// the foreground color and its clear bits the background color.

import GraphiteBase

/// What QuickDraw's shape calls do: FrameRect, PaintRect, EraseRect,
/// InvertRect and FillRect, and their ovals', round rectangles', arcs',
/// polygons' and regions' calls.
public enum ShapeOperation: Hashable, Sendable {
    /// The outline, inside the shape, the pen's size thick, with the pen's
    /// pattern and mode.
    case frame
    /// The shape, with the pen's pattern and mode.
    case paint
    /// The shape, with the background pattern.
    case erase
    /// The shape's pixels inverted.
    case invert
    /// The shape, with a pattern.
    case fill(Pattern)
}

public extension Port {

    /// Draws a region with a pattern and mode, in the port's colors, where
    /// the port can draw.
    func draw(_ region: Region, pattern: Pattern, mode: TransferMode) {
        guard let pixels else { return }
        let area = region.intersection(drawableRegion)
        guard !area.isEmpty else { return }
        let origin = pixelBounds.topLeft
        // The fast case: one color copied over what is there.
        if mode.base == .patCopy, pattern.isSolid {
            let value = pixels.value(for: pattern.rows[0] == 0 ? backColor : foreColor)
            for rect in area.rectangles { pixels.fill(rect, with: value) }
            return
        }
        for rect in area.rectangles {
            for v in rect.top ..< rect.bottom {
                for h in rect.left ..< rect.right {
                    let point = Point(v: v, h: h)
                    let isSet = pattern.isSet(at: point - origin)
                    guard let existing = pixels.color(at: point) else { continue }
                    let color = mode.combine(isForeground: isSet, drawn: foreColor, existing: existing,
                                             fore: foreColor, back: backColor, opColor: opColor)
                    if mode.booleanOperation == 2 || mode.booleanOperation == 6, pixels.format.isIndexed {
                        // Xor on indexed pixels inverts the index's bits, as
                        // QuickDraw does.
                        if (mode.booleanOperation == 2) == isSet, let value = pixels.value(at: point) {
                            pixels.setValue(~value & (1 << UInt32(pixels.format.depth) - 1), at: point)
                        }
                        continue
                    }
                    pixels.setValue(pixels.value(for: color), at: point)
                }
            }
        }
    }

    /// Does one of QuickDraw's shape operations on a region.
    func perform(_ operation: ShapeOperation, on region: Region, outline: () -> Region) {
        switch operation {
        case .frame:
            guard isPenVisible else { return }
            draw(outline(), pattern: pen.pattern, mode: pen.mode)
        case .paint:
            guard isPenVisible else { return }
            draw(region, pattern: pen.pattern, mode: pen.mode)
        case .erase:
            draw(region, pattern: backPattern, mode: .patCopy)
        case .invert:
            draw(region, pattern: .black, mode: .patXor)
        case .fill(let pattern):
            draw(region, pattern: pattern, mode: .patCopy)
        }
    }

    /// FrameRect, PaintRect, EraseRect, InvertRect, FillRect.
    func perform(_ operation: ShapeOperation, rect: Rect) {
        let region = Region(rect: rect)
        perform(operation, on: region) { region.subtracting(Region(rect: rect.insetBy(dh: pen.size.h, dv: pen.size.v))) }
    }

    /// FrameOval, PaintOval, EraseOval, InvertOval, FillOval.
    func perform(_ operation: ShapeOperation, oval rect: Rect) {
        let region = Region.oval(in: rect)
        perform(operation, on: region) { region.subtracting(.oval(in: rect.insetBy(dh: pen.size.h, dv: pen.size.v))) }
    }

    /// FrameRoundRect and the rest.
    func perform(_ operation: ShapeOperation, roundRect rect: Rect, ovalWidth: Int16, ovalHeight: Int16) {
        let region = Region.roundRect(rect, ovalWidth: ovalWidth, ovalHeight: ovalHeight)
        perform(operation, on: region) {
            let inner = Region.roundRect(rect.insetBy(dh: pen.size.h, dv: pen.size.v),
                                         ovalWidth: ovalWidth &- 2 &* pen.size.h, ovalHeight: ovalHeight &- 2 &* pen.size.v)
            return region.subtracting(inner)
        }
    }

    /// FrameArc and the rest: FrameArc draws the oval's edge alone, not the
    /// wedge's sides.
    func perform(_ operation: ShapeOperation, arc rect: Rect, startAngle: Int16, arcAngle: Int16) {
        let region = Region.arc(in: rect, startAngle: startAngle, arcAngle: arcAngle)
        perform(operation, on: region) {
            region.subtracting(.oval(in: rect.insetBy(dh: pen.size.h, dv: pen.size.v)))
        }
    }

    /// FramePoly and the rest: FramePoly draws lines between the points, as
    /// LineTo does.
    func perform(_ operation: ShapeOperation, polygon: Polygon) {
        let region = Region.polygon(polygon)
        perform(operation, on: region) {
            var outline = Region()
            for (a, b) in zip(polygon.points, polygon.points.dropFirst()) {
                outline = outline.union(.line(from: a, to: b, pen: pen.size))
            }
            return outline
        }
    }

    /// FrameRgn and the rest: FrameRgn draws inside the region's edge.
    func perform(_ operation: ShapeOperation, region: Region) {
        perform(operation, on: region) { region.subtracting(region.insetBy(dh: pen.size.h, dv: pen.size.v)) }
    }

    /// LineTo: a line from the pen's location to a point, which becomes the
    /// pen's location.
    func line(to point: Point) {
        if isPenVisible {
            draw(.line(from: pen.location, to: point, pen: pen.size), pattern: pen.pattern, mode: pen.mode)
        }
        pen.location = point
    }

    /// Line: a line by a distance from the pen's location.
    func line(dh: Int16, dv: Int16) {
        line(to: pen.location + Point(v: dv, h: dh))
    }

    /// EraseRect of the port's rectangle, as a new window's is.
    func eraseAll() {
        perform(.erase, rect: portRect)
    }
}
