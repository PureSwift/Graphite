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
    @Test func carbonTextAndDefaultKey() throws {
        let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
        let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 50, bottom: 150, right: 250),
                            items: [DialogItem(bounds: Rect(top: 10, left: 10, bottom: 30, right: 100), kind: .editText),
                                    DialogItem(bounds: Rect(top: 40, left: 10, bottom: 60, right: 80), kind: .button)])
        dialog.defaultItem = 2
        try dialog.attach(to: manager)
        var hits: [Int] = []
        let router = DialogEventRouter(windows: manager, itemHit: { _, hit in hits.append(hit) })
        router.register(dialog)
        var text = CarbonEvent(type: EventType(eventClass: "text", kind: 1), time: 0)
        text.setParameter("text", type: "TEXT", bytes: [65, 66])
        #expect(router.route(text))
        #expect(dialog.text(of: 1)?.bytes == [65, 66])
        var key = CarbonEvent(type: EventType(eventClass: "keyb", kind: 1), time: 0)
        key.setParameter("kchr", type: "char", bytes: [13])
        #expect(router.route(key))
        #expect(hits == [2])
    }

    @Test func dispatchThroughEventTarget() throws {
        let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
        let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 50, bottom: 150, right: 250),
                            items: [DialogItem(bounds: Rect(top: 10, left: 10, bottom: 30, right: 100), kind: .editText)])
        try dialog.attach(to: manager)
        let router = DialogEventRouter(windows: manager, itemHit: { _, _ in })
        router.register(dialog)
        let target = EventTarget()
        let registration = router.install(on: target)
        var event = CarbonEvent(type: EventType(eventClass: "text", kind: 1), time: 0)
        event.setParameter("text", type: "TEXT", bytes: [65])
        #expect(target.send(&event) == .handled)
        #expect(dialog.text(of: 1)?.bytes == [65])
        target.remove(registration)
        #expect(target.send(&event) == .notHandled)
    }

}
