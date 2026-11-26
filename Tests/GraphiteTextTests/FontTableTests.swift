#if FreeType
import Testing
import GraphiteBase
import GraphiteText

/// Needs a font on the machine: the system's, which nothing here checks in.
@Suite struct FontTableTests {

    static let finder = FontFinder()
    static let entry = finder.fonts.first { $0.index == 0 && $0.path.lowercased().hasSuffix(".ttf") }
    static let hasFont = entry != nil

    private func face() throws -> FreeTypeFace {
        let entry = try #require(Self.entry)
        return try FreeTypeFace(path: entry.path, index: entry.index)
    }

    private func int16(_ bytes: [UInt8], at offset: Int) -> Int {
        Int(Int16(bitPattern: UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])))
    }

    @Test(.enabled(if: Self.hasFont)) func theHeadTableIsTheFontHeader() throws {
        let head = try #require(try face().table("head"))
        #expect(head.count == 54)
        // The magic number, then the units per em.
        #expect(Array(head[12 ..< 16]) == [0x5F, 0x0F, 0x3C, 0xF5])
        #expect(int16(head, at: 18) > 0)
    }

    @Test(.enabled(if: Self.hasFont)) func missingTablesAreNil() throws {
        #expect(try face().table("zzzz") == nil)
    }

    @Test(.enabled(if: Self.hasFont)) func tablesAreTheSameAcrossLoads() throws {
        let entry = try #require(Self.entry)
        let fromFile = try face()
        let bytes = try #require(fromFile.table("head"))
        let name = try #require(fromFile.table("name"))
        #expect(name.count > 6)
        #expect(bytes.count == 54)
        #expect(try FreeTypeFace(path: entry.path, index: entry.index).table("head") == bytes)
    }

    @Test(.enabled(if: Self.hasFont)) func horizontalMetricsAreInEms() throws {
        let face = try face()
        let metrics = try #require(face.horizontalMetrics)
        #expect(metrics.ascent > 0 && metrics.ascent < 2)
        #expect(metrics.descent < 0 && metrics.descent > -1)
        #expect(metrics.leading >= 0)
        #expect(metrics.maximumAdvance > 0)
        #expect(metrics.averageAdvance > 0 && metrics.averageAdvance <= metrics.maximumAdvance)
        #expect(metrics.capHeight > 0 && metrics.xHeight > 0 && metrics.xHeight < metrics.capHeight)
        #expect(metrics.underlinePosition < 0 && metrics.underlineThickness > 0)

        // The same ascent and descent as the 'hhea' table gives over the em.
        let head = try #require(face.table("head"))
        let hhea = try #require(face.table("hhea"))
        let em = Double(int16(head, at: 18))
        let hheaAscent = Double(int16(hhea, at: 4)) / em
        let hheaDescent = Double(int16(hhea, at: 6)) / em
        if hheaAscent > 0 {
            #expect(abs(metrics.ascent - hheaAscent) < 0.01)
            #expect(abs(metrics.descent - hheaDescent) < 0.01)
        }
    }

    @Test(.enabled(if: Self.hasFont)) func theBuiltInFontHasNoTables() {
        let system = SystemFont.shared
        #expect(system.table("head") == nil)
        #expect(system.horizontalMetrics == nil)
    }
}
#endif
