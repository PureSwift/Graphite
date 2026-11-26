// QuickDraw's shapes as the regions they cover. A pixel is in a shape when
// its center is, so a shape covers no more than its bounding rectangle;
// frames are drawn inside it, the pen's width and height thick. Lines are
// the pen's rectangle, hanging below and to the right of each point the
// line passes through.

import protocol Foundation.ContiguousBytes
import GraphiteBase

/// A polygon: its points in order, closed or not.
public struct Polygon: Hashable, Sendable {

    public var points: [Point]

    public init(points: [Point]) {
        self.points = points
    }

    /// polyBBox.
    public var bounds: Rect {
        guard let first = points.first else { return .zero }
        var box = Rect(topLeft: first, bottomRight: first)
        for point in points {
            box.top = min(box.top, point.v)
            box.left = min(box.left, point.h)
            box.bottom = max(box.bottom, point.v)
            box.right = max(box.right, point.h)
        }
        return box
    }

    /// The polygon record: polySize, polyBBox, then the points.
    public var record: [UInt8] {
        var writer = BigEndianWriter()
        writer.write(UInt16(truncatingIfNeeded: 10 + 4 * points.count))
        let box = bounds
        for value in [box.top, box.left, box.bottom, box.right] { writer.write(UInt16(bitPattern: value)) }
        for point in points {
            writer.write(UInt16(bitPattern: point.v))
            writer.write(UInt16(bitPattern: point.h))
        }
        return writer.bytes
    }

    /// A polygon record: as many points as polySize says.
    public init(record bytes: some ContiguousBytes) throws(MacError) {
        do {
            var reader = BigEndianReader(bytes)
            let size = Int(try reader.read(UInt16.self))
            guard size >= 10 else { throw MacError.parameter }
            try reader.skip(8)
            points = try (0 ..< (size - 10) / 4).map { _ throws(BigEndianReadError) in
                Point(v: Int16(bitPattern: try reader.read(UInt16.self)), h: Int16(bitPattern: try reader.read(UInt16.self)))
            }
        } catch let error as MacError {
            throw error
        } catch {
            throw .parameter
        }
    }
}

public extension Region {

    /// The rectangles' union, built row by row: for many small rectangles,
    /// such as a line's.
    init(unionOf rectangles: [Rect]) {
        var rows: [Int: [Span]] = [:]
        for rect in rectangles where !rect.isEmpty {
            for row in Int(rect.top) ..< Int(rect.bottom) {
                rows[row, default: []].append(Span(left: Int(rect.left), right: Int(rect.right)))
            }
        }
        self.init(bands: rows.map { Band(top: $0.key, bottom: $0.key + 1, spans: $0.value) })
    }

    /// An oval inscribed in a rectangle.
    static func oval(in rect: Rect) -> Region {
        rows(in: rect) { _ in true }
    }

    /// A rectangle with rounded corners, each a quarter of an oval
    /// `ovalWidth` wide and `ovalHeight` high.
    static func roundRect(_ rect: Rect, ovalWidth: Int16, ovalHeight: Int16) -> Region {
        let width = min(Int(ovalWidth), rect.width), height = min(Int(ovalHeight), rect.height)
        guard width > 0, height > 0 else { return Region(rect: rect) }
        var bands: [Band] = []
        let top = Int(rect.top), bottom = Int(rect.bottom), left = Int(rect.left), right = Int(rect.right)
        let radiusX = Double(width) / 2, radiusY = Double(height) / 2
        for row in top ..< bottom {
            let center = Double(row) + 0.5
            // How far into a corner the row is, from the corner oval's center.
            let dy: Double
            if center < Double(top) + radiusY {
                dy = Double(top) + radiusY - center
            } else if center > Double(bottom) - radiusY {
                dy = center - (Double(bottom) - radiusY)
            } else {
                dy = 0
            }
            let inset = radiusX - radiusX * (max(0, 1 - (dy / radiusY) * (dy / radiusY))).squareRoot()
            let spanLeft = left + Int((inset).rounded()), spanRight = right - Int((inset).rounded())
            if spanLeft < spanRight { bands.append(Band(top: row, bottom: row + 1, spans: [Span(left: spanLeft, right: spanRight)])) }
        }
        return Region(bands: bands)
    }

    /// A wedge of the oval in a rectangle: from `startAngle` through
    /// `arcAngle` degrees (negative is counterclockwise), 0° at twelve
    /// o'clock and angles scaled to the rectangle, as QuickDraw measures
    /// them.
    static func arc(in rect: Rect, startAngle: Int16, arcAngle: Int16) -> Region {
        guard abs(Int(arcAngle)) < 360 else { return oval(in: rect) }
        guard arcAngle != 0 else { return Region() }
        var start = Double(startAngle), extent = Double(arcAngle)
        if extent < 0 {
            start += extent
            extent = -extent
        }
        start = start.truncatingRemainder(dividingBy: 360)
        if start < 0 { start += 360 }
        let centerX = Double(Int(rect.left) + Int(rect.right)) / 2, centerY = Double(Int(rect.top) + Int(rect.bottom)) / 2
        let radiusX = Double(rect.width) / 2, radiusY = Double(rect.height) / 2
        return rows(in: rect) { point in
            let angle = quickDrawAngle(dx: (point.x - centerX) / radiusX, dy: (point.y - centerY) / radiusY)
            var offset = angle - start
            if offset < 0 { offset += 360 }
            return offset < extent
        }
    }

    /// The pixels a polygon encloses, by the even-odd rule at their centers.
    static func polygon(_ polygon: Polygon) -> Region {
        let points = polygon.points
        guard points.count >= 3 else { return Region() }
        let box = polygon.bounds
        var bands: [Band] = []
        for row in Int(box.top) ..< Int(box.bottom) {
            let y = Double(row) + 0.5
            var crossings: [Double] = []
            for (index, a) in points.enumerated() {
                let b = points[(index + 1) % points.count]
                let ay = Double(a.v), by = Double(b.v)
                guard (ay <= y && y < by) || (by <= y && y < ay) else { continue }
                crossings.append(Double(a.h) + (y - ay) / (by - ay) * Double(Int(b.h) - Int(a.h)))
            }
            crossings.sort()
            var spans: [Span] = []
            for pair in stride(from: 0, to: crossings.count - 1, by: 2) {
                // Columns whose centers lie between the crossings.
                let left = Int((crossings[pair] - 0.5).rounded(.up)), right = Int((crossings[pair + 1] - 0.5).rounded(.up))
                if left < right { spans.append(Span(left: left, right: right)) }
            }
            if !spans.isEmpty { bands.append(Band(top: row, bottom: row + 1, spans: spans)) }
        }
        return Region(bands: bands)
    }

    /// A line from one point to another, each point it passes through
    /// covered by the pen's rectangle, `pen.h` wide and `pen.v` high.
    static func line(from start: Point, to end: Point, pen: Point) -> Region {
        guard pen.h > 0, pen.v > 0 else { return Region() }
        var x = Int(start.h), y = Int(start.v)
        let endX = Int(end.h), endY = Int(end.v)
        let dx = abs(endX - x), dy = -abs(endY - y)
        let stepX = x < endX ? 1 : -1, stepY = y < endY ? 1 : -1
        var error = dx + dy
        var rects: [Rect] = []
        while true {
            rects.append(Rect(top: Int16(clamping: y), left: Int16(clamping: x),
                              bottom: Int16(clamping: y + Int(pen.v)), right: Int16(clamping: x + Int(pen.h))))
            if x == endX && y == endY { break }
            let doubled = 2 * error
            if doubled >= dy {
                error += dy
                x += stepX
            }
            if doubled <= dx {
                error += dx
                y += stepY
            }
        }
        return Region(unionOf: rects)
    }

    /// The rows of the oval in a rectangle, each pixel's center tested.
    private static func rows(in rect: Rect, including: ((x: Double, y: Double)) -> Bool) -> Region {
        guard !rect.isEmpty else { return Region() }
        let centerX = Double(Int(rect.left) + Int(rect.right)) / 2, centerY = Double(Int(rect.top) + Int(rect.bottom)) / 2
        let radiusX = Double(rect.width) / 2, radiusY = Double(rect.height) / 2
        var bands: [Band] = []
        for row in Int(rect.top) ..< Int(rect.bottom) {
            let y = Double(row) + 0.5
            let dy = (y - centerY) / radiusY
            guard dy * dy < 1 else { continue }
            let half = radiusX * (1 - dy * dy).squareRoot()
            let first = Int((centerX - half - 0.5).rounded(.up)), last = Int((centerX + half - 0.5).rounded(.up))
            var spans: [Span] = []
            var spanStart: Int?
            for column in first ..< last {
                if including((Double(column) + 0.5, y)) {
                    if spanStart == nil { spanStart = column }
                } else if let begun = spanStart {
                    spans.append(Span(left: begun, right: column))
                    spanStart = nil
                }
            }
            if let begun = spanStart { spans.append(Span(left: begun, right: last)) }
            if !spans.isEmpty { bands.append(Band(top: row, bottom: row + 1, spans: spans)) }
        }
        return Region(bands: bands)
    }
}
