import GraphiteDialogs
import GraphiteEvents
import GraphiteWindows

/// Connects Cacao scenes to one shared Carbon queue and event target.
/// Callers may install additional handlers on `target` and handle events
/// the target declines with `unhandled`.
@MainActor
public final class ToolboxEventDispatcher {
    public let queue: EventQueue
    public let target: EventTarget
    public let router: DialogEventRouter
    public var unhandled: (CarbonEvent) -> Void
    private var dispatching = false

    public init(windows: WindowManager, queue: EventQueue = EventQueue(), target: EventTarget = EventTarget(),
                itemHit: @escaping (Dialog, Int) -> Void, redraw: @escaping (Dialog) -> Void = { _ in },
                unhandled: @escaping (CarbonEvent) -> Void = { _ in }) {
        self.queue = queue
        self.target = target
        self.unhandled = unhandled
        self.router = DialogEventRouter(windows: windows, itemHit: itemHit, redraw: redraw)
        router.install(on: target)
    }

    public func attach(_ scene: ToolboxScene) {
        router.register(scene.dialog)
        scene.eventQueue = queue
        scene.didPostEvent = { [weak self, weak scene] in
            self?.dispatch()
            scene?.invalidate()
        }
    }

    public func detach(_ scene: ToolboxScene) {
        router.unregister(scene.dialog)
        scene.eventQueue = nil
        scene.didPostEvent = nil
    }

    public func dispatch() {
        guard !dispatching else { return }
        dispatching = true
        defer { dispatching = false }
        while var event = queue.receive() {
            if target.send(&event) == .notHandled { unhandled(event) }
        }
    }
}
