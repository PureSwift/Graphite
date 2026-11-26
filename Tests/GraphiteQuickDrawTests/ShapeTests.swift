import Testing
import GraphiteBase
import GraphiteQuickDraw

/// Shapes drawn in 1-bit ports, against snapshots of Graphite's own output
/// checked by eye. They stand in for references from a Mac until there are
/// some.
@Suite struct ShapeTests {

    private func drawn(_ width: Int16, _ height: Int16, _ body: (Port) -> Void) -> String {
        let port = bitmapPort(width: width, height: height)
        body(port)
        return snapshot(port)
    }

    @Test func frameRect() {
        #expect(drawn(8, 6) { $0.perform(.frame, rect: Rect(top: 1, left: 1, bottom: 5, right: 7)) } == """
        ........
        .######.
        .#....#.
        .#....#.
        .######.
        ........
        """)
    }

    @Test func paintOval() {
        #expect(drawn(10, 10) { $0.perform(.paint, oval: Rect(top: 1, left: 1, bottom: 9, right: 9)) } == """
        ..........
        ...####...
        ..######..
        .########.
        .########.
        .########.
        .########.
        ..######..
        ...####...
        ..........
        """)
    }

    @Test func frameOval() {
        #expect(drawn(12, 8) { $0.perform(.frame, oval: Rect(top: 0, left: 0, bottom: 8, right: 12)) } == """
        ...######...
        .##......##.
        ##........##
        #..........#
        #..........#
        ##........##
        .##......##.
        ...######...
        """)
    }

    @Test func paintRoundRect() {
        #expect(drawn(12, 8) { $0.perform(.paint, roundRect: Rect(top: 0, left: 0, bottom: 8, right: 12), ovalWidth: 6, ovalHeight: 6) } == """
        .##########.
        ############
        ############
        ############
        ############
        ############
        ############
        .##########.
        """)
    }

    @Test func paintArc() {
        // From twelve o'clock, clockwise through a quarter.
        #expect(drawn(10, 10) { $0.perform(.paint, arc: Rect(top: 0, left: 0, bottom: 10, right: 10), startAngle: 0, arcAngle: 90) } == """
        .....##...
        .....####.
        .....####.
        .....#####
        .....#####
        ..........
        ..........
        ..........
        ..........
        ..........
        """)
        // The same quarter, counterclockwise from three o'clock.
        let back = drawn(10, 10) { $0.perform(.paint, arc: Rect(top: 0, left: 0, bottom: 10, right: 10), startAngle: 90, arcAngle: -90) }
        let forward = drawn(10, 10) { $0.perform(.paint, arc: Rect(top: 0, left: 0, bottom: 10, right: 10), startAngle: 0, arcAngle: 90) }
        #expect(back == forward)
    }

    @Test func paintPolygon() {
        let triangle = Polygon(points: [Point(v: 0, h: 0), Point(v: 0, h: 9), Point(v: 7, h: 0)])
        #expect(drawn(10, 8) { $0.perform(.paint, polygon: triangle) } == """
        ########..
        #######...
        ######....
        ####......
        ###.......
        ##........
        #.........
        ..........
        """)
    }

    @Test func lines() {
        var location = Point.zero
        let lines = drawn(10, 8) { port in
            port.move(to: Point(v: 0, h: 0))
            port.line(to: Point(v: 7, h: 9))
            port.pen.size = Point(v: 2, h: 2)
            port.move(to: Point(v: 6, h: 0))
            port.line(dh: 4, dv: 0)
            location = port.pen.location
        }
        #expect(location == Point(v: 6, h: 4))
        #expect(lines == """
        #.........
        .#........
        ..##......
        ....#.....
        .....#....
        ......##..
        ######..#.
        ######...#
        """)
    }

    @Test func fillWithAPattern() {
        #expect(drawn(8, 4) { $0.perform(.fill(.gray), rect: Rect(top: 0, left: 0, bottom: 4, right: 8)) } == """
        #.#.#.#.
        .#.#.#.#
        #.#.#.#.
        .#.#.#.#
        """)
    }

    @Test func polygonRecordsRoundTrip() throws {
        let polygon = Polygon(points: [Point(v: 1, h: 2), Point(v: -3, h: 40), Point(v: 7, h: 5)])
        #expect(polygon.bounds == Rect(top: -3, left: 2, bottom: 7, right: 40))
        #expect(try Polygon(record: polygon.record) == polygon)
        #expect(throws: MacError.parameter) { try Polygon(record: [0, 4]) }
    }
}
