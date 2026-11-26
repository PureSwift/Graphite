import Testing
import GraphiteBase
import GraphiteEvents

private final class TestHost: EventLoopHost {
    var eventTime: Double = 0
    var deadline: Double?
    var wakeCount = 0
    func waitForEvents(until deadline: Double?, queue: EventQueue) { self.deadline = deadline }
    func wakeEventLoop() { wakeCount += 1 }
}

private final class WaitingHost: EventLoopHost, ClassicEventHost {
    var eventTime: Double = 0
    var ticks: UInt32 = 60
    var mouseLocation = Point(v: 5, h: 7)
    var modifiers: UInt16 = 0x100
    var onWait: (() -> Void)?
    func waitForEvents(until deadline: Double?, queue: EventQueue) {
        if let deadline { eventTime = deadline }
        onWait?()
    }
    func waitForClassicEvents(until deadline: Double, queue: ClassicEventQueue) {
        eventTime = deadline
        onWait?()
    }
    func wakeEventLoop() {}
}

@Suite struct EventTests {
    let key = EventType(eventClass: "keyb", kind: 1)
    let mouse = EventType(eventClass: "mous", kind: 1)

    @Test func parametersAreCopiedAndTyped() {
        var original = CarbonEvent(type: key, time: 3)
        original.setParameter("----", type: "long", bytes: [1, 2])
        var copy = original
        copy.setParameter("----", type: "TEXT", bytes: [3])
        #expect(original.parameter("----", type: "long")?.bytes == [1, 2])
        #expect(copy.parameter("----", type: "long") == nil)
        #expect(copy.parameter("----")?.bytes == [3])
    }

    @Test func prioritiesFilteringAndPeek() {
        let queue = EventQueue()
        queue.post(CarbonEvent(type: key, time: 1))
        queue.post(CarbonEvent(type: mouse, time: 2), priority: .high)
        queue.post(CarbonEvent(type: key, time: 3), priority: .high)
        #expect(queue.receive(matching: [key], remove: false)?.time == 3)
        #expect(queue.count == 3)
        #expect(queue.receive()?.time == 2)
        #expect(queue.receive()?.time == 3)
        #expect(queue.receive()?.time == 1)
    }

    @Test func classicPeekAndFlushStop() {
        let queue = ClassicEventQueue()
        for kind: UInt16 in [1, 3, 1, 3] { queue.post(ClassicEvent(what: kind)) }
        #expect(queue.next(mask: 1 << 3, remove: false)?.what == 3)
        queue.flush(mask: 1 << 1, stopMask: 1 << 3)
        #expect(queue.next(mask: 0xffff)?.what == 3)
        #expect(queue.next(mask: 0xffff)?.what == 1)
    }

    @Test func handlerChainsAndChanges() {
        let target = EventTarget()
        var order: [Int] = []
        target.install(types: [key]) { _, _ in order.append(1); return .handled }
        let top = target.install(types: [key]) { event, next in
            order.append(2)
            let result = next(&event)
            order.append(3)
            return result
        }
        var event = CarbonEvent(type: key, time: 0)
        #expect(target.send(&event) == .handled)
        #expect(order == [2, 1, 3])
        target.removeTypes([key], from: top)
        order.removeAll()
        #expect(target.send(&event) == .handled)
        #expect(order == [1])
    }

    @Test func hostLoopAndTimers() {
        let host = TestHost()
        let loop = EventLoop(host: host)
        var fired: [UInt64] = []
        let timer = loop.installTimer(delay: 2) { fired.append($0) }
        #expect(!loop.runOne(until: 10))
        #expect(host.deadline == 2)
        host.eventTime = 2
        #expect(loop.runOne())
        #expect(fired == [timer])
        #expect(!loop.runOne(until: 2))
    }

    @Test func inputState() {
        let input = InputState()
        input.setKey(42, down: true)
        #expect(input.isKeyDown(42))
        #expect(input.keyMap[5] == 4)
        input.setKey(42, down: false)
        #expect(!input.isKeyDown(42))
        input.buttons = 1
        #expect(input.buttonDown)
    }

    @Test func receiveWaitsForMatchingEventsAndTimers() {
        let host = WaitingHost()
        let loop = EventLoop(host: host)
        loop.post(CarbonEvent(type: mouse, time: 1))
        loop.installTimer(delay: 2) { _ in loop.post(CarbonEvent(type: key, time: 2)) }
        if case .event(let event) = loop.receive(matching: [key], timeout: 5, remove: false) {
            #expect(event.time == 2)
        } else { Issue.record("Expected matching event") }
        #expect(loop.queue.count == 2)
        if case .timedOut = loop.receive(matching: [EventType(eventClass: "none", kind: 1)], timeout: 0) {} else {
            Issue.record("Expected timeout")
        }
    }

    @Test func classicWaitReturnsNullStateOrPostedEvent() {
        let host = WaitingHost()
        let manager = ClassicEventManager(host: host)
        let empty = manager.waitNext(mask: 2, sleepTicks: 30)
        #expect(!empty.found && empty.event.what == 0)
        #expect(empty.event.where_ == Point(v: 5, h: 7))
        #expect(empty.event.modifiers == 0x100)
        host.onWait = { manager.queue.post(ClassicEvent(what: 1, message: 42)) }
        let received = manager.waitNext(mask: 2, sleepTicks: 60)
        #expect(received.found && received.event.message == 42)
    }

    @Test func registeredHotKeyDeliversItsIdentifier() {
        let target = EventTarget()
        let registry = HotKeyRegistry()
        var identifier: [UInt8] = []
        target.install(types: [EventType(eventClass: "keyb", kind: 5)]) { event, _ in
            identifier = event.parameter("----", type: "hkid")?.bytes ?? []
            return .handled
        }
        #expect(registry.register(keyCode: 12, modifiers: 256, id: HotKeyID(signature: "TEST", id: 7), target: target))
        #expect(!registry.register(keyCode: 12, modifiers: 256, id: HotKeyID(signature: "TEST", id: 8), target: target))
        #expect(registry.send(keyCode: 12, modifiers: 256, pressed: true, time: 1) == .handled)
        #expect(identifier == [84, 69, 83, 84, 0, 0, 0, 7])
        registry.unregister(keyCode: 12, modifiers: 256)
        #expect(registry.send(keyCode: 12, modifiers: 256, pressed: true, time: 1) == .notHandled)
    }
}
