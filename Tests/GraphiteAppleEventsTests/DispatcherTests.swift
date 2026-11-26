import Synchronization
import Testing
import GraphiteBase
import GraphiteAppleEvents

@Suite struct DispatcherTests {

    @Test func handlersByClassIDAndWildcard() throws {
        let dispatcher = AppleEventDispatcher()
        let seen = Mutex<[String]>([])
        func entry(_ eventClass: FourCharCode, _ eventID: FourCharCode, _ name: String, system: Bool = false) -> AppleEventDispatcher.Entry {
            AppleEventDispatcher.Entry(eventClass: eventClass, eventID: eventID, isSystem: system) { _, _ in seen.withLock { $0.append(name) } }
        }
        dispatcher.install(entry("aevt", "oapp", "open"))
        dispatcher.install(entry("aevt", DescriptorType.wildCard, "any core"))
        dispatcher.install(entry(DescriptorType.wildCard, DescriptorType.wildCard, "anything", system: true))
        dispatcher.install(entry("misc", "dosc", "system script", system: true))
        var reply = Descriptor.null
        for (eventClass, eventID) in [("aevt", "oapp"), ("aevt", "quit"), ("misc", "dosc"), ("core", "getd")] as [(FourCharCode, FourCharCode)] {
            try dispatcher.dispatch(AppleEvent(eventClass: eventClass, eventID: eventID), reply: &reply)
        }
        #expect(seen.withLock { $0 } == ["open", "any core", "system script", "anything"])
        #expect(dispatcher.entry(eventClass: "aevt", eventID: "oapp")?.eventID == "oapp")
        #expect(dispatcher.entry(eventClass: "aevt", eventID: "odoc") == nil)
    }

    @Test func installingAgainReplaces() throws {
        let dispatcher = AppleEventDispatcher()
        dispatcher.install(.init(eventClass: "aevt", eventID: "quit", procedure: 1) { _, _ in })
        dispatcher.install(.init(eventClass: "aevt", eventID: "quit", procedure: 2) { _, _ in })
        #expect(dispatcher.entry(eventClass: "aevt", eventID: "quit")?.procedure == 2)
        #expect(throws: MacError.handlerNotFound) { try dispatcher.remove(eventClass: "aevt", eventID: "quit", procedure: 1) }
        try dispatcher.remove(eventClass: "aevt", eventID: "quit", procedure: 2)
        #expect(throws: MacError.handlerNotFound) { try dispatcher.remove(eventClass: "aevt", eventID: "quit") }
        #expect(throws: MacError.eventNotHandled) {
            var reply = Descriptor.null
            try dispatcher.dispatch(AppleEvent(eventClass: "aevt", eventID: "quit"), reply: &reply)
        }
    }

    @Test func sendingToItself() throws {
        let dispatcher = AppleEventDispatcher()
        dispatcher.install(.init(eventClass: "test", eventID: "echo") { event, reply in
            reply[AppleEvent.Parameter.directObject] = event[parameter: AppleEvent.Parameter.directObject]
        })
        dispatcher.install(.init(eventClass: "test", eventID: "fail") { _, _ throws(MacError) in throw .corruptData })
        var event = AppleEvent(eventClass: "test", eventID: "echo", target: AppleEvent.currentProcess)
        event[parameter: AppleEvent.Parameter.directObject] = Descriptor(text: "hello")
        let reply = try dispatcher.send(event, mode: .waitReply)
        #expect(try AppleEvent(reply).eventID == "ansr")
        #expect(reply[AppleEvent.Parameter.directObject] == Descriptor(text: "hello"))
        #expect(try dispatcher.send(event).isNull)
        // A handler's error goes in the reply; the send succeeds.
        let failed = try dispatcher.send(AppleEvent(eventClass: "test", eventID: "fail"), mode: .waitReply)
        #expect(failed[AppleEvent.Parameter.errorNumber]?.load(as: Int32.self) == -1702)
        // No handler: an error only to a sender that waits.
        #expect(throws: MacError.eventNotHandled) { try dispatcher.send(AppleEvent(eventClass: "none", eventID: "none"), mode: .waitReply) }
        _ = try dispatcher.send(AppleEvent(eventClass: "none", eventID: "none"))
        // Another process isn't running here.
        let elsewhere = AppleEvent(eventClass: "test", eventID: "echo", target: Descriptor(type: DescriptorType.kernelProcessID, integer: Int32(1)))
        #expect(throws: MacError.processNotFound) { try dispatcher.send(elsewhere) }
    }

    @Test func requiredEvents() throws {
        let dispatcher = AppleEventDispatcher()
        #expect(!dispatcher.sendCoreEvent(AppleEvent.Core.quitApplication))
        let opened = Mutex<[String]>([])
        dispatcher.install(.init(eventClass: AppleEvent.Core.eventClass, eventID: AppleEvent.Core.openDocuments) { event, _ in
            let list = event[parameter: AppleEvent.Parameter.directObject]?.items ?? []
            opened.withLock { $0 = list.compactMap { FileURLCoding().path(of: $0.descriptor) } }
        })
        #expect(dispatcher.sendOpenDocuments(["/tmp/a", "/tmp/b c"]))
        #expect(opened.withLock { $0 } == ["/tmp/a", "/tmp/b c"])
    }
}
