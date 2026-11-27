import Testing
import GraphiteBase
import GraphiteDialogs
import GraphiteEvents
import GraphiteQuickDraw
import GraphiteWindows

@Suite struct DialogEventRouterTests {
    @Test func mouseTrackingAndKeyboard() throws {
        let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
        let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 50, bottom: 150, right: 250),
                            items: [DialogItem(bounds: Rect(top: 10, left: 10, bottom: 30, right: 80), kind: .button, text: "OK")])
        dialog.defaultItem = 1
        try dialog.attach(to: manager)
        var hits: [Int] = []
        let router = DialogEventRouter(windows: manager, itemHit: { _, hit in hits.append(hit) })
        router.register(dialog)
        #expect(router.route(ClassicEvent(what: 1, location: Point(v: 65, h: 65))))
        #expect(hits.isEmpty)
        #expect(router.route(ClassicEvent(what: 2, location: Point(v: 65, h: 65))))
        #expect(hits == [1])
        #expect(router.route(ClassicEvent(what: 3, message: 13)))
        #expect(hits == [1, 1])
        #expect(!router.route(ClassicEvent(what: 1, location: Point(v: 300, h: 300))))
    }

    @Test func carbonMouseUsesGlobalCoordinates() throws {
        let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
        let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 50, bottom: 150, right: 250),
                            items: [DialogItem(bounds: Rect(top: 10, left: 10, bottom: 30, right: 80), kind: .button)])
        try dialog.attach(to: manager)
        var hits = 0
        let router = DialogEventRouter(windows: manager, itemHit: { _, _ in hits += 1 })
        router.register(dialog)
        func event(_ kind: UInt32) -> CarbonEvent {
            var result = CarbonEvent(type: EventType(eventClass: "mous", kind: kind), time: 0)
            var bytes = BigEndianWriter()
            bytes.write(Float(65).bitPattern); bytes.write(Float(65).bitPattern)
            result.setParameter("mloc", type: "hipt", bytes: bytes.bytes)
            return result
        }
        #expect(router.route(event(1)))
        #expect(router.route(event(5)))
        #expect(router.route(event(2)))
        #expect(hits == 1)
    }
}
