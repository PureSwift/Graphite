#if GRAPHITE_SDL3
import Testing
import GraphiteBase
import GraphiteEvents
import GraphiteSDLEvents
import SDL3Swift

@Suite(.serialized) struct SDLEventHostTests {
    @Test func translatesInputAndForwardsOtherEvents() throws {
        try SDL.initialize(subSystems: [.events])
        defer { SDL.quit() }
        var quitReceived = false
        let host = try SDLEventHost(globalPosition: { _, x, y in (x + 100, y + 200) }) { event in
            if case .quit = event { quitReceived = true }
        }
        let queue = EventQueue()
        host.wakeEventLoop()
        host.waitForEvents(until: host.eventTime + 1, queue: queue)
        #expect(queue.count == 0)
        host.process(.keyDown(windowID: 1, scancode: Scancode(rawValue: 4), keycode: Keycode(rawValue: 97), modifiers: .shift, isRepeat: false), queue: queue)
        let key = try #require(queue.receive())
        #expect(key.type == EventType(eventClass: "keyb", kind: 1))
        #expect(key.parameter("kcod", type: "magn")?.bytes == [0, 0, 0, 0])
        #expect(key.parameter("kmod", type: "magn")?.bytes == [0, 0, 2, 0])
        #expect(host.input.isKeyDown(0))
        host.process(.mouseButtonDown(windowID: 1, which: MouseID(rawValue: 0), button: .left, clicks: 1, x: 3, y: 4), queue: queue)
        let mouse = try #require(queue.receive())
        #expect(mouse.type == EventType(eventClass: "mous", kind: 1))
        #expect(host.input.mouse == Point(v: 204, h: 103))
        #expect(host.input.buttonDown)
        host.process(.quit, queue: queue)
        #expect(quitReceived)
    }
}
#endif
