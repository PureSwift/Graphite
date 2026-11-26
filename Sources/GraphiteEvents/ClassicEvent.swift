import GraphiteBase
import Synchronization

/// The classic EventRecord; the host supplies ticks and global mouse state.
public struct ClassicEvent: Hashable, Sendable {
    public var what: UInt16
    public var message: UInt32
    public var when: UInt32
    public var where_: Point
    public var modifiers: UInt16

    public init(what: UInt16, message: UInt32 = 0, when: UInt32 = 0,
                location: Point = .zero, modifiers: UInt16 = 0) {
        self.what = what
        self.message = message
        self.when = when
        self.where_ = location
        self.modifiers = modifiers
    }
}

/// The classic queue supports EventAvail's peek, GetNextEvent's removal,
/// and FlushEvents' stop mask. Event masks have one bit per event code.
public final class ClassicEventQueue: Sendable {
    private let events = Mutex<[ClassicEvent]>([])
    public init() {}
    public func post(_ event: ClassicEvent) { events.withLock { $0.append(event) } }
    public func next(mask: UInt16, remove: Bool = true) -> ClassicEvent? {
        events.withLock { queue in
            guard let index = queue.firstIndex(where: { Self.matches($0, mask) }) else { return nil }
            return remove ? queue.remove(at: index) : queue[index]
        }
    }
    public func flush(mask: UInt16, stopMask: UInt16 = 0) {
        events.withLock { queue in
            let stop = queue.firstIndex { Self.matches($0, stopMask) } ?? queue.endIndex
            queue.replaceSubrange(0..<stop, with: queue[..<stop].filter { !Self.matches($0, mask) })
        }
    }
    private static func matches(_ event: ClassicEvent, _ mask: UInt16) -> Bool {
        event.what < 16 && (mask & (UInt16(1) << event.what)) != 0
    }
}

/// The host blocks until input, a mouse-region transition, or the deadline.
/// The deadline is in seconds on the host's monotonic event clock.
public protocol ClassicEventHost: AnyObject {
    var eventTime: Double { get }
    var ticks: UInt32 { get }
    var mouseLocation: Point { get }
    var modifiers: UInt16 { get }
    func waitForClassicEvents(until deadline: Double, queue: ClassicEventQueue)
}

/// Classic Event Manager retrieval over a host's event source.
public final class ClassicEventManager {
    public let queue: ClassicEventQueue
    public let host: any ClassicEventHost

    public init(host: any ClassicEventHost, queue: ClassicEventQueue = ClassicEventQueue()) {
        self.host = host
        self.queue = queue
    }

    /// A missing event is represented by a null event with current input state.
    public func next(mask: UInt16, remove: Bool = true) -> (found: Bool, event: ClassicEvent) {
        if let event = queue.next(mask: mask, remove: remove) { return (true, event) }
        return (false, nullEvent())
    }

    /// WaitNextEvent's sleep is in 60 Hz ticks. `mouseInside`, when supplied,
    /// returns false after the mouse leaves the caller's region.
    public func waitNext(mask: UInt16, sleepTicks: UInt32,
                         mouseInside: ((Point) -> Bool)? = nil) -> (found: Bool, event: ClassicEvent) {
        let deadline = host.eventTime + Double(sleepTicks) / 60
        while true {
            if let event = queue.next(mask: mask) { return (true, event) }
            if let mouseInside, !mouseInside(host.mouseLocation) { return (false, nullEvent()) }
            guard host.eventTime < deadline else { return (false, nullEvent()) }
            host.waitForClassicEvents(until: deadline, queue: queue)
        }
    }

    private func nullEvent() -> ClassicEvent {
        ClassicEvent(what: 0, when: host.ticks, location: host.mouseLocation, modifiers: host.modifiers)
    }
}
