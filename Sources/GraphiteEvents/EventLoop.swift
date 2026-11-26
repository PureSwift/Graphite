/// The host waits for input until the supplied monotonic deadline. A nil
/// deadline means no timeout. It posts received events to the loop's queue.
public protocol EventLoopHost: AnyObject {
    var eventTime: Double { get }
    func waitForEvents(until deadline: Double?, queue: EventQueue)
    func wakeEventLoop()
}

/// The result of waiting for a Carbon event.
public enum EventReceiveResult: Sendable {
    case event(CarbonEvent)
    case timedOut
    case quit
}

/// A host-driven Carbon event loop. Call its methods on the loop's thread;
/// other threads can post to the queue and wake the host.
public final class EventLoop {
    private struct Timer {
        let id: UInt64
        var fireTime: Double
        var interval: Double
        let callback: (UInt64) -> Void
    }
    public let queue: EventQueue
    public let target: EventTarget
    public let host: any EventLoopHost
    private var timers: [Timer] = []
    private var nextTimer: UInt64 = 1
    private var shouldQuit = false

    public init(host: any EventLoopHost, queue: EventQueue = EventQueue(), target: EventTarget = EventTarget()) {
        self.host = host
        self.queue = queue
        self.target = target
    }

    public func post(_ event: CarbonEvent, priority: EventPriority = .standard) {
        queue.post(event, priority: priority)
        host.wakeEventLoop()
    }

    @discardableResult
    public func installTimer(delay: Double, interval: Double = 0, callback: @escaping (UInt64) -> Void) -> UInt64 {
        let id = nextTimer
        nextTimer &+= 1
        timers.append(Timer(id: id, fireTime: host.eventTime + max(0, delay), interval: max(0, interval), callback: callback))
        host.wakeEventLoop()
        return id
    }

    public func removeTimer(_ id: UInt64) { timers.removeAll { $0.id == id } }
    public func setTimer(_ id: UInt64, delay: Double) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[index].fireTime = host.eventTime + max(0, delay)
        host.wakeEventLoop()
    }
    public func quit() { shouldQuit = true; host.wakeEventLoop() }

    /// Wait for a matching event, running timers while the host waits. A nil
    /// timeout waits indefinitely; zero checks the queue without waiting.
    public func receive(matching types: Set<EventType> = [], timeout: Double? = nil,
                        remove: Bool = true) -> EventReceiveResult {
        let deadline = timeout.map { host.eventTime + max(0, $0) }
        while true {
            if shouldQuit { return .quit }
            if let event = queue.receive(matching: types, remove: remove) { return .event(event) }
            let now = host.eventTime
            if let deadline, now >= deadline { return .timedOut }
            if fireDueTimer(at: now) { continue }
            let timerDeadline = timers.map(\.fireTime).min()
            let wake = [deadline, timerDeadline].compactMap { $0 }.min()
            host.waitForEvents(until: wake, queue: queue)
        }
    }

    private func fireDueTimer(at now: Double) -> Bool {
        guard let index = timers.indices.filter({ timers[$0].fireTime <= now }).min(by: { timers[$0].fireTime < timers[$1].fireTime }) else { return false }
        let timer = timers[index]
        if timer.interval > 0 { timers[index].fireTime = now + timer.interval }
        else { timers.remove(at: index) }
        timer.callback(timer.id)
        return true
    }

    /// Dispatch one event or a due timer; if neither is ready, wait once.
    @discardableResult
    public func runOne(until deadline: Double? = nil) -> Bool {
        let now = host.eventTime
        if fireDueTimer(at: now) { return true }
        if var event = queue.receive() {
            _ = target.send(&event)
            return true
        }
        guard !shouldQuit, deadline == nil || now < deadline! else { return false }
        let timerDeadline = timers.map(\.fireTime).min()
        let wake = [deadline, timerDeadline].compactMap { $0 }.min()
        host.waitForEvents(until: wake, queue: queue)
        return false
    }

    public func run() {
        shouldQuit = false
        while !shouldQuit { _ = runOne() }
    }
}
