import Testing
import GraphiteBase
import GraphiteQuickDraw
import GraphiteText

@Suite struct GlyphMetricsTests {

    let fonts = FontRegistry()

    private func layout(_ text: String, width: Double? = nil, runs: [TextRun]? = nil) -> TextLayout {
        TextLayout(text: text, runs: runs ?? [TextRun(range: 0 ..< text.unicodeScalars.count)], fonts: fonts, width: width)
    }

    // MARK: Metrics

    @Test func inkIsRoundedOutward() {
        let metrics = GlyphMetrics(advance: 7.5, leftSideBearing: -0.5, top: 9.2, width: 5.1, height: 9.2)
        #expect(metrics.inkBox.left == -1)
        #expect(metrics.inkBox.top == 10)
        #expect(metrics.inkBox.width == 6)
        #expect(metrics.inkBox.height == 10)
        #expect(metrics.rightSideBearing == 7.5 - (-0.5 + 5.1))
        #expect(metrics.hasInk)
        #expect(!GlyphMetrics(advance: 4, leftSideBearing: 0, top: 0, width: 0, height: 0).hasInk)
    }

    @Test func aFaceWithoutNumbersGivesItsImagesAsMetrics() throws {
        let face = SystemFont.shared
        let image = try #require(face.glyph(for: "H", size: 12))
        let metrics = try #require(face.glyphMetrics(for: "H", size: 12))
        #expect(metrics.advance == Double(image.advance))
        // The image is a cell with margins; the ink is the box of its set pixels.
        #expect(metrics.hasInk)
        #expect(metrics.width < Double(image.width) && metrics.height < Double(image.height))
        #expect(metrics.leftSideBearing >= Double(image.left) && metrics.top <= Double(image.top))
        let rightColumns = Int(metrics.leftSideBearing) - image.left + Int(metrics.width)
        let bottomRows = Int(Double(image.top) - metrics.top) + Int(metrics.height)
        #expect(rightColumns <= image.width && bottomRows <= image.height)
        #expect((0 ..< image.width).contains { image.coverage[(Int(Double(image.top) - metrics.top)) * image.width + $0] != 0 })
        let space = try #require(face.glyphMetrics(for: " ", size: 12))
        #expect(!space.hasInk && space.advance > 0)
        #expect(face.glyphMetrics(for: "\u{10FFFF}", size: 12) == nil)
    }

    @Test func glyphsAreNamedByTheirCharacters() {
        let face = SystemFont.shared
        #expect(face.glyphID(for: "H") == 0x48)
        #expect(face.glyphID(for: "\u{10FFFF}") == 0)
    }

    // MARK: Layout records

    @Test func recordsFollowTheCharacters() {
        let layout = layout("Hi")
        let records = layout.glyphRecords()
        #expect(records.map(\.offset) == [0, 1])
        #expect(records.map(\.glyphID) == [0x48, 0x69])
        #expect(records.map(\.x) == [0, 8])
        #expect(records.map(\.line) == [0, 0])
    }

    @Test func recordsSkipLineBreaksAndKeepLines() {
        let layout = layout("a\rb\ncd")
        let records = layout.glyphRecords()
        #expect(records.map(\.offset) == [0, 2, 4, 5])
        #expect(records.map(\.line) == [0, 1, 2, 2])
        #expect(records.map(\.x).prefix(3) == [0, 0, 0])
    }

    @Test func recordsOfARange() {
        let layout = layout("abcdef")
        #expect(layout.glyphRecords(in: 2 ..< 4).map(\.offset) == [2, 3])
        #expect(layout.glyphRecords(in: 4 ..< 40).map(\.offset) == [4, 5])
        #expect(layout.glyphRecords(in: 9 ..< 12).isEmpty)
        #expect(self.layout("").glyphRecords().isEmpty)
    }

    @Test func recordsUseEachRunsFace() {
        // A glyph a face hasn't has glyph 0, so the registry's built-in face
        // and a made-up family agree for ASCII.
        let layout = layout("ab", runs: [TextRun(range: 0 ..< 1, size: 12), TextRun(range: 1 ..< 2, size: 24)])
        #expect(layout.glyphRecords().map(\.glyphID) == [0x61, 0x62])
    }

    // MARK: Ink

    @Test func inkIsInsideTheLayout() throws {
        let layout = layout("Hi!")
        let ink = try #require(layout.inkBounds())
        #expect(ink.left >= 0 && ink.top >= 0)
        #expect(Double(ink.right) <= layout.width + 2)
        #expect(Int(ink.bottom) <= layout.height)
        #expect(ink.width > 0 && ink.height > 0)
        // The H stands on the baseline: its ink goes down to it.
        let first = try #require(layout.inkBounds(of: 0 ..< 1))
        #expect(Int(first.bottom) == layout.lines[0].baseline)
        #expect(first.top < first.bottom)
    }

    @Test func inkOfARangeIsInsideInkOfTheWhole() throws {
        let layout = layout("Hello")
        let whole = try #require(layout.inkBounds())
        let part = try #require(layout.inkBounds(of: 1 ..< 3))
        #expect(part.left >= whole.left && part.right <= whole.right)
        #expect(part.top >= whole.top && part.bottom <= whole.bottom)
        #expect(part.width < whole.width)
    }

    @Test func spacesDrawNothing() {
        #expect(layout("   ").inkBounds() == nil)
        #expect(layout("").inkBounds() == nil)
        #expect(layout("a b").inkBounds(of: 1 ..< 2) == nil)
        #expect(layout("abc").inkBounds(of: 10 ..< 12) == nil)
    }

    @Test func laterLinesAreLower() throws {
        let layout = layout("a\rb")
        let first = try #require(layout.inkBounds(of: 0 ..< 1))
        let second = try #require(layout.inkBounds(of: 2 ..< 3))
        #expect(second.top > first.top)
        #expect(Int(second.bottom) == layout.lines[1].baseline)
        let both = try #require(layout.inkBounds())
        #expect(both.top == first.top && both.bottom == second.bottom)
    }
}

#if FreeType
@Suite struct FreeTypeGlyphMetricsTests {

    static let finder = FontFinder()
    static let entry = finder.fonts.first { $0.index == 0 && $0.path.lowercased().hasSuffix(".ttf") }
    static let hasFont = entry != nil

    private func face() throws -> FreeTypeFace {
        let entry = try #require(Self.entry)
        return try FreeTypeFace(path: entry.path, index: entry.index)
    }

    @Test(.enabled(if: Self.hasFont)) func metricsAgreeWithTheRenderedGlyph() throws {
        let face = try face()
        let image = try #require(face.glyph(for: "H", size: 24))
        let metrics = try #require(face.glyphMetrics(for: "H", size: 24))
        #expect(abs(metrics.advance - Double(image.advance)) <= 0.5)
        #expect(metrics.inkBox.left == image.left)
        #expect(metrics.inkBox.top == image.top)
        #expect(abs(metrics.inkBox.width - image.width) <= 1)
        #expect(abs(metrics.inkBox.height - image.height) <= 1)
        #expect(metrics.hasInk)
        #expect(metrics.rightSideBearing > -2)
    }

    @Test(.enabled(if: Self.hasFont)) func metricsScaleWithSize() throws {
        let face = try face()
        let small = try #require(face.glyphMetrics(for: "H", size: 12))
        let large = try #require(face.glyphMetrics(for: "H", size: 48))
        #expect(large.height > small.height * 3)
        #expect(large.advance > small.advance * 3)
    }

    @Test(.enabled(if: Self.hasFont)) func spacesAndMissingCharacters() throws {
        let face = try face()
        let space = try #require(face.glyphMetrics(for: " ", size: 24))
        #expect(!space.hasInk && space.advance > 0)
        #expect(face.glyphMetrics(for: "\u{10FFFF}", size: 24) == nil)
        #expect(face.glyphID(for: "\u{10FFFF}") == 0)
    }

    @Test(.enabled(if: Self.hasFont)) func glyphIDsAreTheFontsOwn() throws {
        let face = try face()
        let h = face.glyphID(for: "H"), i = face.glyphID(for: "i")
        #expect(h != 0 && i != 0 && h != i)
        #expect(face.glyphID(for: "H") == h)
    }

    @Test(.enabled(if: Self.hasFont)) func layoutRecordsAndInkUseTheFace() throws {
        let fonts = FontRegistry()
        let number = fonts.register(try face())
        let layout = TextLayout(text: "Hi", runs: [TextRun(range: 0 ..< 2, family: number, size: 24)], fonts: fonts)
        let face = try face()
        #expect(layout.glyphRecords().map(\.glyphID) == [face.glyphID(for: "H"), face.glyphID(for: "i")])
        let ink = try #require(layout.inkBounds())
        #expect(ink.width > 10 && ink.height > 10)
        #expect(Int(ink.bottom) <= layout.lines[0].baseline + 1)
    }
}
#endif
