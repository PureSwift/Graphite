// Regions: any set of pixels, kept as horizontal bands, each a run of rows
// with the same spans of columns; rectangles are one band of one span. A
// QuickDraw region record (rgnSize, rgnBBox, then the points where each
// scanline's inside and outside change from the one above it, ending in
// 0x7FFF) is read and written for programs that keep regions in their
// memory.

import protocol Foundation.ContiguousBytes
import GraphiteBase

public struct Region: Hashable, Sendable {

    /// Columns from `left` up to `right`.
    struct Span: Hashable, Sendable {
        var left: Int
        var right: Int
    }

    /// Rows from `top` up to `bottom`, with the same spans.
    struct Band: Hashable, Sendable {
        var top: Int
        var bottom: Int
        var spans: [Span]
    }

    /// Top to bottom, none empty, none touching another with the same spans.
    private(set) var bands: [Band]

    /// The empty region.
    public init() {
        bands = []
    }

    /// RectRgn.
    public init(rect: Rect) {
        bands = rect.isEmpty ? [] : [Band(top: Int(rect.top), bottom: Int(rect.bottom), spans: [Span(left: Int(rect.left), right: Int(rect.right))])]
    }

    init(bands: [Band]) {
        self.bands = Self.normalized(bands)
    }

    public var isEmpty: Bool { bands.isEmpty }

    /// rgnBBox.
    public var bounds: Rect {
        guard let first = bands.first, let last = bands.last else { return .zero }
        let left = bands.map { $0.spans.first!.left }.min()!
        let right = bands.map { $0.spans.last!.right }.max()!
        return Rect(top: Self.clamp(first.top), left: Self.clamp(left), bottom: Self.clamp(last.bottom), right: Self.clamp(right))
    }

    /// Whether it is its bounding rectangle.
    public var isRectangular: Bool {
        bands.count <= 1 && (bands.first?.spans.count ?? 1) == 1
    }

    /// The rectangles it is made of, top to bottom and left to right.
    public var rectangles: [Rect] {
        bands.flatMap { band in
            band.spans.map { Rect(top: Self.clamp(band.top), left: Self.clamp($0.left), bottom: Self.clamp(band.bottom), right: Self.clamp($0.right)) }
        }
    }

    /// PtInRgn.
    public func contains(_ point: Point) -> Bool {
        let v = Int(point.v), h = Int(point.h)
        guard let band = bands.first(where: { $0.top <= v && v < $0.bottom }) else { return false }
        return band.spans.contains { $0.left <= h && h < $0.right }
    }

    /// RectInRgn: whether any of the rectangle is in the region.
    public func intersects(_ rect: Rect) -> Bool {
        !intersection(Region(rect: rect)).isEmpty
    }

    // MARK: Combining

    /// UnionRgn.
    public func union(_ other: Region) -> Region { Self.combine(self, other) { $0 || $1 } }

    /// SectRgn.
    public func intersection(_ other: Region) -> Region { Self.combine(self, other) { $0 && $1 } }

    /// DiffRgn: this region less the other.
    public func subtracting(_ other: Region) -> Region { Self.combine(self, other) { $0 && !$1 } }

    /// XorRgn.
    public func symmetricDifference(_ other: Region) -> Region { Self.combine(self, other) { $0 != $1 } }

    /// OffsetRgn.
    public func offsetBy(dh: Int16, dv: Int16) -> Region {
        Region(bands: bands.map { band in
            Band(top: band.top + Int(dv), bottom: band.bottom + Int(dv),
                 spans: band.spans.map { Span(left: $0.left + Int(dh), right: $0.right + Int(dh)) })
        })
    }

    /// InsetRgn: each edge moved in by dh and dv, out for negative ones.
    public func insetBy(dh: Int16, dv: Int16) -> Region {
        var region = self
        let h = Int(dh), v = Int(dv)
        if h != 0 {
            region = Region(bands: region.bands.map { band in
                Band(top: band.top, bottom: band.bottom,
                     spans: band.spans.map { Span(left: $0.left + h, right: $0.right - h) }.filter { $0.left < $0.right })
            })
        }
        if v > 0 {
            // A row stays where every row within v of it is in the region.
            var eroded = region
            for offset in 1 ... v {
                eroded = eroded.intersection(region.offsetBy(dh: 0, dv: Int16(offset)))
                eroded = eroded.intersection(region.offsetBy(dh: 0, dv: Int16(-offset)))
            }
            region = eroded
        } else if v < 0 {
            region = Region(bands: region.bands.map { Band(top: $0.top + v, bottom: $0.bottom - v, spans: $0.spans) })
        }
        return region
    }

    private static func combine(_ a: Region, _ b: Region, _ inside: (Bool, Bool) -> Bool) -> Region {
        var edges = Set<Int>()
        for band in a.bands + b.bands {
            edges.insert(band.top)
            edges.insert(band.bottom)
        }
        let rows = edges.sorted()
        var result: [Band] = []
        for (top, bottom) in zip(rows, rows.dropFirst()) {
            let spans = combine(a.spans(at: top), b.spans(at: top), inside)
            if !spans.isEmpty { result.append(Band(top: top, bottom: bottom, spans: spans)) }
        }
        return Region(bands: result)
    }

    private static func combine(_ a: [Span], _ b: [Span], _ inside: (Bool, Bool) -> Bool) -> [Span] {
        var edges = Set<Int>()
        for span in a + b {
            edges.insert(span.left)
            edges.insert(span.right)
        }
        let columns = edges.sorted()
        var spans: [Span] = []
        for (left, right) in zip(columns, columns.dropFirst()) {
            let inA = a.contains { $0.left <= left && left < $0.right }
            let inB = b.contains { $0.left <= left && left < $0.right }
            guard inside(inA, inB) else { continue }
            if let last = spans.last, last.right == left {
                spans[spans.count - 1].right = right
            } else {
                spans.append(Span(left: left, right: right))
            }
        }
        return spans
    }

    /// The spans of the band a row is in.
    private func spans(at row: Int) -> [Span] {
        bands.first { $0.top <= row && row < $0.bottom }?.spans ?? []
    }

    /// Bands sorted, without empty ones, adjacent ones with the same spans
    /// joined, and each band's spans sorted and joined where they touch.
    private static func normalized(_ bands: [Band]) -> [Band] {
        var result: [Band] = []
        for var band in bands.sorted(by: { $0.top < $1.top }) where band.top < band.bottom {
            var spans: [Span] = []
            for span in band.spans.sorted(by: { $0.left < $1.left }) where span.left < span.right {
                if let last = spans.last, span.left <= last.right {
                    spans[spans.count - 1].right = max(last.right, span.right)
                } else {
                    spans.append(span)
                }
            }
            guard !spans.isEmpty else { continue }
            band.spans = spans
            if let last = result.last, last.bottom == band.top, last.spans == band.spans {
                result[result.count - 1].bottom = band.bottom
            } else {
                result.append(band)
            }
        }
        return result
    }

    private static func clamp(_ value: Int) -> Int16 {
        Int16(clamping: value)
    }

    // MARK: QuickDraw's record

    /// The region record: rgnSize, rgnBBox and, for one that isn't a
    /// rectangle, its scanlines' inversion points. rgnSize is the record's
    /// size; for a region over 32 KB, as Carbon allows, its low 15 bits.
    public var record: [UInt8] {
        var writer = BigEndianWriter()
        writer.write(UInt16(0))
        let box = bounds
        for value in [box.top, box.left, box.bottom, box.right] { writer.write(UInt16(bitPattern: value)) }
        if !isRectangular {
            var rows = Set<Int>()
            for band in bands {
                rows.insert(band.top)
                rows.insert(band.bottom)
            }
            var above: [Span] = []
            for row in rows.sorted() {
                let here = spans(at: row)
                let points = Self.edges(of: above).symmetricDifference(Self.edges(of: here)).sorted()
                above = here
                guard !points.isEmpty else { continue }
                writer.write(UInt16(bitPattern: Self.clamp(row)))
                for point in points { writer.write(UInt16(bitPattern: Self.clamp(point))) }
                writer.write(UInt16(0x7FFF))
            }
            writer.write(UInt16(0x7FFF))
        }
        _ = writer.set(UInt16(truncatingIfNeeded: writer.count), at: 0)
        return writer.bytes
    }

    private static func edges(of spans: [Span]) -> Set<Int> {
        var edges = Set<Int>()
        for span in spans {
            edges.insert(span.left)
            edges.insert(span.right)
        }
        return edges
    }

    /// A region record. A record of 10 bytes is its rectangle; past those,
    /// its scanlines. Throws for one that ends early or whose points don't
    /// pair up.
    public init(record bytes: some ContiguousBytes) throws(MacError) {
        do {
            var reader = BigEndianReader(bytes)
            let size = Int(try reader.read(UInt16.self))
            let top = Int16(bitPattern: try reader.read(UInt16.self)), left = Int16(bitPattern: try reader.read(UInt16.self))
            let bottom = Int16(bitPattern: try reader.read(UInt16.self)), right = Int16(bitPattern: try reader.read(UInt16.self))
            let box = Rect(top: top, left: left, bottom: bottom, right: right)
            guard size > 10, reader.remaining >= 2 else {
                self.init(rect: box)
                return
            }
            var inverted = Set<Int>()
            var result: [Band] = []
            var row: Int?
            while true {
                let value = Int16(bitPattern: try reader.read(UInt16.self))
                if value == 0x7FFF { break }
                let next = Int(value)
                if let row, !inverted.isEmpty {
                    let points = inverted.sorted()
                    guard points.count % 2 == 0 else { throw MacError.parameter }
                    let spans = stride(from: 0, to: points.count, by: 2).map { Span(left: points[$0], right: points[$0 + 1]) }
                    result.append(Band(top: row, bottom: next, spans: spans))
                }
                while true {
                    let point = Int16(bitPattern: try reader.read(UInt16.self))
                    if point == 0x7FFF { break }
                    if !inverted.insert(Int(point)).inserted { inverted.remove(Int(point)) }
                }
                row = next
            }
            guard inverted.isEmpty else { throw MacError.parameter }
            self.init(bands: result)
        } catch let error as MacError {
            throw error
        } catch {
            throw .parameter
        }
    }
}
