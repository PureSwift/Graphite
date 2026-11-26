/// A handler either handles an event, declines it, or reports a status.
public enum EventHandlingResult: Equatable, Sendable {
    case handled
    case notHandled
    case error(Int32)
}

/// The continuation supplied to a handler invokes the next matching handler.
public typealias EventHandler = (inout CarbonEvent, (inout CarbonEvent) -> EventHandlingResult) -> EventHandlingResult

/// Installed handlers are called newest first. A handler may explicitly call
/// the continuation to wrap the rest of the chain; returning notHandled
/// without doing so automatically passes the event along.
public final class EventTarget {
    private struct Registration {
        let id: UInt64
        var types: Set<EventType>
        let handler: EventHandler
    }
    private var registrations: [Registration] = []
    private var nextID: UInt64 = 1

    public init() {}

    @discardableResult
    public func install(types: Set<EventType>, handler: @escaping EventHandler) -> UInt64 {
        let id = nextID
        nextID &+= 1
        registrations.insert(Registration(id: id, types: types, handler: handler), at: 0)
        return id
    }

    public func remove(_ id: UInt64) { registrations.removeAll { $0.id == id } }
    public func addTypes(_ types: Set<EventType>, to id: UInt64) {
        guard let index = registrations.firstIndex(where: { $0.id == id }) else { return }
        registrations[index].types.formUnion(types)
    }
    public func removeTypes(_ types: Set<EventType>, from id: UInt64) {
        guard let index = registrations.firstIndex(where: { $0.id == id }) else { return }
        registrations[index].types.subtract(types)
    }

    public func send(_ event: inout CarbonEvent) -> EventHandlingResult {
        let handlers = registrations.filter { $0.types.contains(event.type) }.map(\.handler)
        func dispatch(_ index: Int, _ event: inout CarbonEvent) -> EventHandlingResult {
            guard index < handlers.count else { return .notHandled }
            var calledNext = false
            let result = handlers[index](&event) { nextEvent in
                calledNext = true
                return dispatch(index + 1, &nextEvent)
            }
            return result == .notHandled && !calledNext ? dispatch(index + 1, &event) : result
        }
        return dispatch(0, &event)
    }
}
