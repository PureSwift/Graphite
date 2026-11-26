// ATSUI's layouts: text with styles over ranges of its characters, broken
// into lines at a width, measured, hit-tested and drawn. Each run is drawn
// as QuickDraw draws text in its font, size and face, so the styles a face
// hasn't look the same in both.

import GraphiteBase
import GraphiteQuickDraw

/// A style over a range of a layout's characters (ATSUSetRunStyle).
public struct TextRun: Hashable, Sendable {

    /// Character offsets into the layout's text.
    public var range: Range<Int>
    public var family: Int16
    public var size: Int
    public var style: TextStyle
    public var color: RGBColor

    public init(range: Range<Int>, family: Int16 = 0, size: Int = 12, style: TextStyle = [], color: RGBColor = .black) {
        self.range = range
        self.family = family
        self.size = size
        self.style = style
        self.color = color
    }
}

public struct TextLayout {

    /// A character placed on a line.
    public struct Character: Hashable, Sendable {
        /// Its offset in the text.
        public var offset: Int
        /// Left edge from the layout's left, and its advance.
        public var x: Double
        public var advance: Double
    }

    public struct Line {
        /// Offsets of the line's characters, a line break's included.
        public var range: Range<Int>
        public var characters: [Character]
        public var width: Double
        public var ascent: Int
        public var descent: Int
        /// The line's baseline from the layout's top.
        public var baseline: Int
        fileprivate var segments: [(run: TextRun, range: Range<Int>, x: Double)]
    }

    public let scalars: [Unicode.Scalar]
    public let runs: [TextRun]
    public private(set) var lines: [Line] = []
    public let fonts: FontRegistry

    /// A layout of `text` in runs (the text outside every run is drawn in
    /// the first), broken at `width` pixels at the last space that fits, and
    /// at every return or newline; nil breaks only at those.
    public init(text: String, runs: [TextRun], fonts: FontRegistry, width limit: Double? = nil) {
        scalars = Array(text.unicodeScalars)
        self.fonts = fonts
        let fallback = runs.first ?? TextRun(range: 0 ..< scalars.count)
        var covered = [TextRun?](repeating: nil, count: scalars.count)
        for run in runs {
            for index in run.range where index >= 0 && index < scalars.count { covered[index] = run }
        }
        self.runs = runs
        var start = 0
        while start < scalars.count || (start == 0 && scalars.isEmpty) {
            lines.append(breakLine(from: start, covered: covered.map { $0 ?? fallback }, limit: limit, fallback: fallback))
            start = lines.last!.range.upperBound
            if scalars.isEmpty { break }
        }
        var top = 0
        for index in lines.indices {
            top += lines[index].ascent
            lines[index].baseline = top
            top += lines[index].descent
        }
    }

    private func port(for run: TextRun) -> Port {
        let port = Port(portRect: .zero)
        port.text.font = run.family
        port.text.size = Int16(clamping: run.size)
        port.text.face = run.style.rawValue
        return port
    }

    private func breakLine(from start: Int, covered: [TextRun], limit: Double?, fallback: TextRun) -> Line {
        var end = start
        var x = 0.0
        var lastSpace: Int?
        var characters: [Character] = []
        var ascent = 0, descent = 0
        var segments: [(run: TextRun, range: Range<Int>, x: Double)] = []
        scan: while end < scalars.count {
            let run = covered[end]
            let scratch = port(for: run)
            let metrics = scratch.fontInfo(fonts: fonts)
            let isBreak = scalars[end] == "\n" || scalars[end] == "\r"
            let advance = isBreak ? 0 : Double(scratch.textWidth([scalars[end]], fonts: fonts))
            if let limit, !isBreak, x + advance > limit, end > start {
                if let space = lastSpace {
                    characters.removeAll { $0.offset > space }
                    end = space + 1
                    segments = segments.compactMap { segment in
                        segment.range.lowerBound >= end ? nil : (segment.run, segment.range.lowerBound ..< min(segment.range.upperBound, end), segment.x)
                    }
                }
                break scan
            }
            characters.append(Character(offset: end, x: x, advance: advance))
            if let last = segments.last, last.run == run {
                segments[segments.count - 1].range = last.range.lowerBound ..< end + 1
            } else {
                segments.append((run, end ..< end + 1, x))
            }
            ascent = max(ascent, Int(metrics.ascent) + Int(metrics.leading))
            descent = max(descent, Int(metrics.descent))
            x += advance
            end += 1
            if scalars[end - 1] == " " { lastSpace = end - 1 }
            if isBreak { break scan }
        }
        if characters.isEmpty {
            let metrics = port(for: fallback).fontInfo(fonts: fonts)
            ascent = Int(metrics.ascent)
            descent = Int(metrics.descent)
        }
        let width = characters.last.map { $0.x + $0.advance } ?? 0
        let finalEnd = max(end, start)
        return Line(range: start ..< finalEnd, characters: characters, width: width, ascent: ascent, descent: descent, baseline: 0, segments: segments)
    }

    // MARK: Measuring

    /// The widest line.
    public var width: Double { lines.map(\.width).max() ?? 0 }

    /// All the lines' height.
    public var height: Int { lines.reduce(0) { $0 + $1.ascent + $1.descent } }

    /// The line a character offset is on; the last for an offset past the end.
    public func lineIndex(containing offset: Int) -> Int {
        lines.firstIndex { $0.range.contains(offset) } ?? max(0, lines.count - 1)
    }

    /// ATSUOffsetToPosition: where a character offset's left edge is, its
    /// line's baseline below the top.
    public func position(ofOffset offset: Int) -> (x: Double, baseline: Int) {
        let line = lines[lineIndex(containing: offset)]
        if let character = line.characters.first(where: { $0.offset == offset }) { return (character.x, line.baseline) }
        return (line.width, line.baseline)
    }

    /// ATSUPositionToOffset: the offset of the character whose box holds the
    /// point, or of the nearer edge past a line's ends.
    public func offset(atX x: Double, y: Int) -> Int {
        var line = lines.last!
        for candidate in lines where y < candidate.baseline + candidate.descent {
            line = candidate
            break
        }
        for character in line.characters where x < character.x + character.advance {
            return x < character.x + character.advance / 2 ? character.offset : character.offset + 1
        }
        return line.range.upperBound
    }

    // MARK: Drawing

    /// ATSUDrawText: the layout with its top left at a point of the port,
    /// in the port's own state afterwards.
    public func draw(in port: Port, at origin: Point) {
        let saved = (port.text, port.foreColor, port.pen.location)
        defer { (port.text, port.foreColor, port.pen.location) = saved }
        for line in lines {
            for segment in line.segments {
                port.text.font = segment.run.family
                port.text.size = Int16(clamping: segment.run.size)
                port.text.face = segment.run.style.rawValue
                port.foreColor = segment.run.color
                port.move(to: Point(v: origin.v &+ Int16(clamping: line.baseline), h: origin.h &+ Int16(clamping: Int(segment.x.rounded()))))
                let characters = scalars[segment.range].filter { $0 != "\n" && $0 != "\r" }
                port.drawText(characters, fonts: fonts)
            }
        }
    }
}

extension FontRegistry: PictureTextDrawer {

    /// A picture's text, at the port's pen in the port's text settings.
    public func drawText(macRoman bytes: [UInt8], in port: Port) {
        port.drawText(macRoman: bytes, fonts: self)
    }
}
