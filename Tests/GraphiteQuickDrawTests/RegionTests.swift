import Testing
import GraphiteBase
import GraphiteQuickDraw

@Suite struct RegionTests {

    let a = Region(rect: Rect(top: 0, left: 0, bottom: 10, right: 10))
    let b = Region(rect: Rect(top: 5, left: 5, bottom: 15, right: 15))

    @Test func rectangles() {
        #expect(a.isRectangular)
        #expect(a.bounds == Rect(top: 0, left: 0, bottom: 10, right: 10))
        #expect(a.contains(Point(v: 9, h: 9)))
        #expect(!a.contains(Point(v: 10, h: 9)))
        #expect(Region(rect: Rect(top: 5, left: 5, bottom: 5, right: 10)).isEmpty)
    }

    @Test func union() {
        let union = a.union(b)
        #expect(!union.isRectangular)
        #expect(union.bounds == Rect(top: 0, left: 0, bottom: 15, right: 15))
        #expect(union.contains(Point(v: 12, h: 12)))
        #expect(!union.contains(Point(v: 12, h: 2)))
        #expect(union.rectangles.count == 3)
    }

    @Test func intersectionDifferenceAndXor() {
        #expect(a.intersection(b) == Region(rect: Rect(top: 5, left: 5, bottom: 10, right: 10)))
        let difference = a.subtracting(b)
        #expect(difference.contains(Point(v: 2, h: 7)))
        #expect(!difference.contains(Point(v: 7, h: 7)))
        let xor = a.symmetricDifference(b)
        #expect(!xor.contains(Point(v: 7, h: 7)))
        #expect(xor.contains(Point(v: 12, h: 12)) && xor.contains(Point(v: 2, h: 2)))
        #expect(a.subtracting(a).isEmpty)
        // Pieces that make a rectangle again are one.
        let halves = Region(rect: Rect(top: 0, left: 0, bottom: 10, right: 5)).union(Region(rect: Rect(top: 0, left: 5, bottom: 10, right: 10)))
        #expect(halves == a)
        #expect(halves.isRectangular)
    }

    @Test func offsetAndInset() {
        #expect(a.offsetBy(dh: 3, dv: -2).bounds == Rect(top: -2, left: 3, bottom: 8, right: 13))
        #expect(a.insetBy(dh: 2, dv: 3) == Region(rect: Rect(top: 3, left: 2, bottom: 7, right: 8)))
        #expect(a.insetBy(dh: -1, dv: -1) == Region(rect: Rect(top: -1, left: -1, bottom: 11, right: 11)))
        // An L shape shrinks on each of its edges.
        let shape = a.union(b).insetBy(dh: 1, dv: 1)
        #expect(!shape.contains(Point(v: 0, h: 5)))
        #expect(shape.contains(Point(v: 1, h: 1)))
        #expect(!shape.contains(Point(v: 14, h: 14)))
    }

    @Test func recordsRoundTrip() throws {
        let rectangle = a.record
        #expect(rectangle.count == 10)
        #expect(Array(rectangle[0 ..< 2]) == [0, 10])
        #expect(try Region(record: rectangle) == a)
        let shapes = [a.union(b), a.symmetricDifference(b), a.subtracting(b), a.union(b.offsetBy(dh: 40, dv: 0))]
        for shape in shapes {
            let record = shape.record
            #expect(Int(record[0]) << 8 | Int(record[1]) == record.count)
            #expect(try Region(record: record) == shape)
        }
    }

    @Test func recordsByHand() throws {
        // A 10×10 square at the origin as QuickDraw writes a non-rectangular
        // region's scanlines: inversions at 0 and 10.
        let bytes: [UInt8] = [0, 28, 0, 0, 0, 0, 0, 10, 0, 10, 0, 0, 0, 0, 0, 10, 0x7F, 0xFF, 0, 10, 0, 0, 0, 10, 0x7F, 0xFF, 0x7F, 0xFF]
        #expect(try Region(record: bytes) == a)
        #expect(throws: MacError.self) { try Region(record: [0, 20, 0, 0, 0, 0, 0, 10, 0, 10, 0, 0]) }
    }
}
