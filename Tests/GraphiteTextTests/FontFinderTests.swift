#if FreeType
import Testing
import GraphiteText

/// Needs fonts on the machine: the system's, which nothing here checks in.
@Suite struct FontFinderTests {

    static let finder = FontFinder()
    static let hasFont = !finder.fonts.isEmpty

    @Test(.enabled(if: Self.hasFont)) func noFaceIsListedTwice() {
        // Folders inside others (Supplemental is in Fonts) don't list a file again.
        let keys = Self.finder.fonts.map { "\($0.path)#\($0.index)" }
        #expect(Set(keys).count == keys.count)
    }

    @Test(.enabled(if: Self.hasFont)) func everyFaceOfAFileIsListedOnce() throws {
        var indices: [String: [Int]] = [:]
        for entry in Self.finder.fonts { indices[entry.path, default: []].append(entry.index) }
        // A sample of the files: each opens its first face to be checked.
        for (path, listed) in indices.sorted(by: { $0.key < $1.key }).prefix(150) {
            let count = try FreeTypeFace(path: path).faceCount
            #expect(count >= 1)
            #expect(listed.first == 0, "\(path)")
            #expect(Set(listed).count == listed.count, "\(path)")
            #expect(listed.allSatisfy { (0 ..< count).contains($0) }, "\(path)")
        }
    }

    @Test(.enabled(if: Self.hasFont)) func collectionsAreListedWholeWhereTheirFacesOpen() throws {
        var indices: [String: [Int]] = [:]
        for entry in Self.finder.fonts { indices[entry.path, default: []].append(entry.index) }
        for (path, listed) in indices where listed.count > 1 {
            let face = try FreeTypeFace(path: path)
            // Past the old cap of 32, and not stopped by one face that wouldn't open.
            let opening = (0 ..< face.faceCount).filter { (try? FreeTypeFace(path: path, index: $0)) != nil }
            #expect(listed == opening, "\(path)")
        }
    }

    @Test(.enabled(if: Self.hasFont)) func anOrdinaryFontHasOneFace() throws {
        let entry = try #require(Self.finder.fonts.first { $0.path.lowercased().hasSuffix(".ttf") })
        let face = try FreeTypeFace(path: entry.path)
        #expect(face.faceCount == 1)
        #expect(Self.finder.fonts.filter { $0.path == entry.path }.count == 1)
    }
}
#endif
