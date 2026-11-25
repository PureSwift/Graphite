import Testing
import GraphiteBase

@Suite struct GeometryTests {

    @Test func pointArithmeticWraps() {
        #expect(Point(v: 1, h: 2) + Point(v: 10, h: 20) == Point(v: 11, h: 22))
        #expect(Point(v: 1, h: 2) - Point(v: 10, h: 20) == Point(v: -9, h: -18))
        #expect(Point(v: .max, h: 0) + Point(v: 1, h: 0) == Point(v: .min, h: 0))
    }

    @Test func setRectOrder() {
        let rect = Rect(left: 1, top: 2, right: 3, bottom: 4)
        #expect(rect == Rect(top: 2, left: 1, bottom: 4, right: 3))
        #expect(rect.width == 2 && rect.height == 2)
    }

    @Test func emptiness() {
        #expect(Rect.zero.isEmpty)
        #expect(Rect(top: 0, left: 10, bottom: 10, right: 10).isEmpty)
        #expect(Rect(top: 10, left: 0, bottom: 0, right: 10).isEmpty)
        #expect(!Rect(top: 0, left: 0, bottom: 1, right: 1).isEmpty)
    }

    @Test func containsExcludesRightAndBottomEdges() {
        let rect = Rect(top: 0, left: 0, bottom: 10, right: 10)
        #expect(rect.contains(Point(v: 0, h: 0)))
        #expect(rect.contains(Point(v: 9, h: 9)))
        #expect(!rect.contains(Point(v: 10, h: 5)))
        #expect(!rect.contains(Point(v: 5, h: 10)))
        #expect(!rect.contains(Point(v: -1, h: 5)))
        #expect(rect.contains(Rect(top: 2, left: 2, bottom: 10, right: 10)))
        #expect(!rect.contains(Rect(top: 2, left: 2, bottom: 11, right: 10)))
        #expect(rect.contains(Rect(top: 50, left: 50, bottom: 50, right: 50)))
    }

    @Test func intersection() {
        let a = Rect(top: 0, left: 0, bottom: 10, right: 10)
        let b = Rect(top: 5, left: 5, bottom: 15, right: 15)
        #expect(a.intersection(b) == Rect(top: 5, left: 5, bottom: 10, right: 10))
        #expect(a.intersects(b))
        let apart = Rect(top: 20, left: 20, bottom: 30, right: 30)
        #expect(a.intersection(apart) == .zero)
        #expect(!a.intersects(apart))
        // Touching edges share no pixels.
        #expect(!a.intersects(Rect(top: 0, left: 10, bottom: 10, right: 20)))
    }

    @Test func unionIncludesEmptyRectangles() {
        let a = Rect(top: 0, left: 0, bottom: 10, right: 10)
        #expect(a.union(Rect(top: 5, left: 5, bottom: 15, right: 20)) == Rect(top: 0, left: 0, bottom: 15, right: 20))
        #expect(a.union(Rect(top: 30, left: 30, bottom: 30, right: 30)) == Rect(top: 0, left: 0, bottom: 30, right: 30))
    }

    @Test func offsetAndInset() {
        var rect = Rect(top: 0, left: 0, bottom: 10, right: 20)
        rect.offset(dh: 5, dv: -5)
        #expect(rect == Rect(top: -5, left: 5, bottom: 5, right: 25))
        #expect(rect.insetBy(dh: 2, dv: 1) == Rect(top: -4, left: 7, bottom: 4, right: 23))
        #expect(rect.insetBy(dh: -2, dv: -1) == Rect(top: -6, left: 3, bottom: 6, right: 27))
    }

    @Test func pin() {
        let rect = Rect(top: 10, left: 10, bottom: 20, right: 20)
        #expect(rect.pin(Point(v: 15, h: 15)) == Point(v: 15, h: 15))
        #expect(rect.pin(Point(v: 0, h: 0)) == Point(v: 10, h: 10))
        #expect(rect.pin(Point(v: 100, h: 100)) == Point(v: 19, h: 19))
        #expect(rect.pin(Point(v: 20, h: 5)) == Point(v: 19, h: 10))
    }

    @Test func enclosingPoints() {
        #expect(Rect(enclosing: Point(v: 10, h: 2), Point(v: 3, h: 8)) == Rect(top: 3, left: 2, bottom: 10, right: 8))
        var rect = Rect.zero
        rect.bottomRight = Point(v: 4, h: 6)
        #expect(rect.topLeft == .zero && rect.width == 6 && rect.height == 4)
    }
}
