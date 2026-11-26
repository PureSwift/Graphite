import Synchronization

/// Carbon queue priorities; events of equal priority retain posting order.
public enum EventPriority: Int, Comparable, Sendable {
    case low = 0, standard = 1, high = 2
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A thread-safe queue. Waiting and waking the host's event loop are the
/// responsibility of the host; retrieving an event never removes other types.
public final class EventQueue: Sendable {
    private struct Entry: Sendable {
        var event: CarbonEvent
        var priority: EventPriority
    }
    private let entries = Mutex<[Entry]>([])

    public init() {}

    public func post(_ event: CarbonEvent, priority: EventPriority = .standard) {
        entries.withLock { queue in
            let index = queue.firstIndex { $0.priority < priority } ?? queue.endIndex
            queue.insert(Entry(event: event, priority: priority), at: index)
        }
    }

    /// An empty type set matches every event. `remove: false` peeks.
    public func receive(matching types: Set<EventType> = [], remove: Bool = true) -> CarbonEvent? {
        entries.withLock { queue in
            guard let index = queue.firstIndex(where: { types.isEmpty || types.contains($0.event.type) }) else { return nil }
            return remove ? queue.remove(at: index).event : queue[index].event
        }
    }

    public var count: Int { entries.withLock { $0.count } }
    public func flush() { entries.withLock { $0.removeAll() } }
}
