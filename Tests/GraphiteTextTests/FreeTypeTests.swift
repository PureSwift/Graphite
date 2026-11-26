#if FreeType
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Testing
import GraphiteBase
import GraphiteQuickDraw
import GraphiteText

/// Needs a font on the machine: the system's, which nothing here checks in.
@Suite struct FreeTypeTests {

    static let finder = FontFinder()
    static let entry = finder.fonts.first { $0.index == 0 && $0.path.lowercased().hasSuffix(".ttf") } ?? finder.fonts.first
    static let hasFont = entry != nil

    private func face() throws -> FreeTypeFace {
        let entry = try #require(Self.entry)
        return try FreeTypeFace(path: entry.path, index: entry.index)
    }

    @Test(.enabled(if: Self.hasFont)) func glyphsAndMetrics() throws {
        let face = try face()
        let metrics = face.metrics(size: 24)
        #expect(metrics.ascent > 10 && metrics.descent > 0)
        #expect(face.metrics(size: 48).ascent > metrics.ascent)
        let glyph = try #require(face.glyph(for: "H", size: 24))
        #expect(glyph.width > 0 && glyph.height > 0 && glyph.advance > 0)
        #expect(glyph.coverage.count == glyph.width * glyph.height)
        #expect(glyph.coverage.contains { $0 > 200 })
        #expect(face.contains("H"))
        let space = try #require(face.glyph(for: " ", size: 24))
        #expect(space.width == 0 && space.advance > 0)
        #expect(face.glyph(for: "\u{10FFFF}", size: 24) == nil)
    }

    @Test(.enabled(if: Self.hasFont)) func loadsFromMemoryToo() throws {
        let entry = try #require(Self.entry)
        let file = try #require(fopen(entry.path, "rb"))
        defer { fclose(file) }
        var bytes: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 65536)
        while case let count = fread(&chunk, 1, chunk.count, file), count > 0 { bytes += chunk[0 ..< count] }
        let face = try FreeTypeFace(data: bytes, index: entry.index)
        #expect(face.familyName == entry.family)
        #expect(face.glyph(for: "H", size: 16) != nil)
        #expect(throws: FreeTypeFace.LoadError.unreadable) { try FreeTypeFace(data: [1, 2, 3]) }
        #expect(throws: FreeTypeFace.LoadError.unreadable) { try FreeTypeFace(path: "/nonexistent.ttf") }
    }

    @Test(.enabled(if: Self.hasFont)) func theFinderFindsFamiliesInAnyCase() throws {
        let entry = try #require(Self.entry)
        let found = try #require(Self.finder.face(family: entry.family.uppercased()))
        #expect(found.familyName == entry.family)
        #expect(Self.finder.face(family: "No Such Family") == nil)
    }

    @Test(.enabled(if: Self.hasFont)) func drawsThroughTheRegistry() throws {
        let entry = try #require(Self.entry)
        let fonts = FontRegistry(lookUp: Self.finder.lookUp)
        let number = fonts.register(try face())
        let port = Port(pixels: PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: 40, right: 80), format: .argb32))
        port.perform(.erase, rect: port.portRect)
        port.text.font = number
        port.text.size = 24
        port.move(to: Point(v: 30, h: 4))
        port.drawText("Hi".unicodeScalars, fonts: fonts)
        var dark = 0
        for v in Int16(0) ..< 40 { for h in Int16(0) ..< 80 where port.pixels?.color(at: Point(v: v, h: h)) != .white { dark += 1 } }
        #expect(dark > 40)
        #expect(port.pen.location.h > 4 + 10)
        // A name the registry hasn't is found by the host's lookup.
        #expect(fonts.face(named: entry.family) is FreeTypeFace)
    }
}
#endif
