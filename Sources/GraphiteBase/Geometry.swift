// QuickDraw's coordinates: 16-bit points and rectangles, with the
// arithmetic of SetRect through PinRect. A rectangle's right and bottom
// edges are outside it, as the lines between pixels QuickDraw draws on.

/// A point in QuickDraw's plane, vertical coordinate first, as QuickDraw
/// keeps it.
public struct Point: Hashable, Sendable {

    public var v: Int16

    public var h: Int16

    public init(v: Int16, h: Int16) {
        self.v = v
        self.h = h
    }

    public init(h: Int16, v: Int16) {
        self.init(v: v, h: h)
    }

    public static var zero: Point { Point(v: 0, h: 0) }
}

public extension Point {

    /// AddPt: each coordinate added, wrapping as 16-bit arithmetic does.
    static func + (lhs: Point, rhs: Point) -> Point {
        Point(v: lhs.v &+ rhs.v, h: lhs.h &+ rhs.h)
    }

    /// SubPt: each coordinate subtracted, wrapping.
    static func - (lhs: Point, rhs: Point) -> Point {
        Point(v: lhs.v &- rhs.v, h: lhs.h &- rhs.h)
    }

    static func += (lhs: inout Point, rhs: Point) {
        lhs = lhs + rhs
    }

    static func -= (lhs: inout Point, rhs: Point) {
        lhs = lhs - rhs
    }
}

/// A rectangle in QuickDraw's plane, its edges in QuickDraw's order: top,
/// left, bottom, right.
public struct Rect: Hashable, Sendable {

    public var top: Int16

    public var left: Int16

    public var bottom: Int16

    public var right: Int16

    public init(top: Int16, left: Int16, bottom: Int16, right: Int16) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    /// SetRect's order: left, top, right, bottom.
    public init(left: Int16, top: Int16, right: Int16, bottom: Int16) {
        self.init(top: top, left: left, bottom: bottom, right: right)
    }

    public init(topLeft: Point, bottomRight: Point) {
        self.init(top: topLeft.v, left: topLeft.h, bottom: bottomRight.v, right: bottomRight.h)
    }

    /// Pt2Rect: the smallest rectangle with both points at its corners.
    public init(enclosing a: Point, _ b: Point) {
        self.init(top: min(a.v, b.v), left: min(a.h, b.h), bottom: max(a.v, b.v), right: max(a.h, b.h))
    }

    public static var zero: Rect { Rect(top: 0, left: 0, bottom: 0, right: 0) }
}

public extension Rect {

    var topLeft: Point {
        get { Point(v: top, h: left) }
        set {
            top = newValue.v
            left = newValue.h
        }
    }

    var bottomRight: Point {
        get { Point(v: bottom, h: right) }
        set {
            bottom = newValue.v
            right = newValue.h
        }
    }

    /// The width, which a rectangle as wide as the plane makes larger than
    /// 16 bits hold.
    var width: Int { Int(right) - Int(left) }

    var height: Int { Int(bottom) - Int(top) }

    /// EmptyRect: no pixels inside, its right edge at or before its left or
    /// its bottom at or above its top.
    var isEmpty: Bool { right <= left || bottom <= top }

    /// PtInRect: the pixel below and right of the point is inside.
    func contains(_ point: Point) -> Bool {
        point.h >= left && point.h < right && point.v >= top && point.v < bottom
    }

    /// Every pixel of the other rectangle is in this one. An empty
    /// rectangle is in every rectangle.
    func contains(_ other: Rect) -> Bool {
        other.isEmpty || (other.left >= left && other.right <= right && other.top >= top && other.bottom <= bottom)
    }

    /// OffsetRect: moved by `dh` across and `dv` down.
    mutating func offset(dh: Int16, dv: Int16) {
        left = left &+ dh
        right = right &+ dh
        top = top &+ dv
        bottom = bottom &+ dv
    }

    func offsetBy(dh: Int16, dv: Int16) -> Rect {
        var rect = self
        rect.offset(dh: dh, dv: dv)
        return rect
    }

    /// InsetRect: each side moved in by `dh` and `dv`; negative numbers
    /// move them out.
    mutating func inset(dh: Int16, dv: Int16) {
        left = left &+ dh
        right = right &- dh
        top = top &+ dv
        bottom = bottom &- dv
    }

    func insetBy(dh: Int16, dv: Int16) -> Rect {
        var rect = self
        rect.inset(dh: dh, dv: dv)
        return rect
    }

    /// SectRect: the pixels in both, or `.zero` when there are none.
    func intersection(_ other: Rect) -> Rect {
        let result = Rect(top: max(top, other.top), left: max(left, other.left),
                          bottom: min(bottom, other.bottom), right: min(right, other.right))
        return result.isEmpty ? .zero : result
    }

    /// SectRect's answer: whether any pixel is in both.
    func intersects(_ other: Rect) -> Bool {
        !intersection(other).isEmpty
    }

    /// UnionRect: the smallest rectangle around both, empty or not.
    func union(_ other: Rect) -> Rect {
        Rect(top: min(top, other.top), left: min(left, other.left),
             bottom: max(bottom, other.bottom), right: max(right, other.right))
    }

    /// PinRect: the nearest point inside the rectangle, its last row and
    /// column being the bottom and right edges less one.
    func pin(_ point: Point) -> Point {
        var h = point.h, v = point.v
        if h < left { h = left }
        if h >= right { h = right &- 1 }
        if v < top { v = top }
        if v >= bottom { v = bottom &- 1 }
        return Point(v: v, h: h)
    }
}
