// A glyph's metrics at a size, as ATSUGlyphGetScreenMetrics gives them:
// fractions of a pixel, from which the whole-pixel box its ink fills is
// taken.

/// Distances in pixels at the size asked for. `top` is above the baseline
/// and `leftSideBearing` right of the pen; both are negative the other way.
public struct GlyphMetrics: Hashable, Sendable {

    /// How far the pen moves after the glyph.
    public var advance: Double
    public var leftSideBearing: Double
    public var top: Double
    public var width: Double
    public var height: Double

    public init(advance: Double, leftSideBearing: Double, top: Double, width: Double, height: Double) {
        self.advance = advance
        self.leftSideBearing = leftSideBearing
        self.top = top
        self.width = width
        self.height = height
    }

    /// The metrics of a glyph image, whole pixels: the ink is the smallest
    /// box holding its coverage, since an image may be a cell with margins
    /// around the glyph, as the built-in font's are.
    public init(image: GlyphImage) {
        var firstColumn = Int.max, lastColumn = -1
        var firstRow = Int.max, lastRow = -1
        for row in 0 ..< image.height {
            for column in 0 ..< image.width where image.coverage[row * image.width + column] != 0 {
                firstColumn = min(firstColumn, column)
                lastColumn = max(lastColumn, column)
                firstRow = min(firstRow, row)
                lastRow = max(lastRow, row)
            }
        }
        guard lastColumn >= 0 else {
            self.init(advance: Double(image.advance), leftSideBearing: Double(image.left), top: Double(image.top), width: 0, height: 0)
            return
        }
        self.init(advance: Double(image.advance), leftSideBearing: Double(image.left + firstColumn),
                  top: Double(image.top - firstRow), width: Double(lastColumn - firstColumn + 1), height: Double(lastRow - firstRow + 1))
    }

    /// Between the right edge of the ink and the pen's next position.
    public var rightSideBearing: Double { advance - (leftSideBearing + width) }

    /// Whether the glyph draws anything: a space doesn't.
    public var hasInk: Bool { width > 0 && height > 0 }

    /// The whole pixels the ink is in: its left from the pen, rounded down;
    /// its top above the baseline, rounded up; and its size, rounded up.
    public var inkBox: (left: Int, top: Int, width: Int, height: Int) {
        (Int(leftSideBearing.rounded(.down)), Int(top.rounded(.up)), Int(width.rounded(.up)), Int(height.rounded(.up)))
    }
}
