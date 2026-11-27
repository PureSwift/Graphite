import GraphiteBase
import GraphiteEvents
import GraphiteWindows

/// Routes shared event-queue input to attached dialogs. Events that do not
/// belong to a dialog are left to the application's other event handlers.
public final class DialogEventRouter {
    public let windows: WindowManager
    private var dialogs: [Dialog] = []
    private weak var trackingDialog: Dialog?
    public var itemHit: (Dialog, Int) -> Void
    public var redraw: (Dialog) -> Void

    public init(windows: WindowManager, itemHit: @escaping (Dialog, Int) -> Void,
                redraw: @escaping (Dialog) -> Void = { _ in }) {
        self.windows = windows
        self.itemHit = itemHit
        self.redraw = redraw
    }

    public func register(_ dialog: Dialog) {
        guard !dialogs.contains(where: { $0 === dialog }) else { return }
        dialogs.append(dialog)
    }

    public func unregister(_ dialog: Dialog) {
        dialogs.removeAll { $0 === dialog }
        if trackingDialog === dialog { trackingDialog = nil }
    }

    private func dialog(for window: Window?) -> Dialog? {
        guard let window else { return nil }
        return dialogs.first { $0.window === window && $0.isVisible }
    }

    private func deliver(_ event: DialogEvent, to dialog: Dialog) {
        var number = 0
        if StandardDialogFilter().filter(dialog, event, &number) {
            itemHit(dialog, number)
        } else if let number = dialog.handle(event) {
            itemHit(dialog, number)
        }
        redraw(dialog)
    }

    /// Route mouse and key EventRecords; other events remain unconsumed.
    @discardableResult
    public func route(_ event: ClassicEvent) -> Bool {
        switch event.what {
        case 1:
            let found = windows.findWindow(at: event.where_)
            guard found.part == .content, let dialog = dialog(for: found.window),
                  let window = dialog.window else { return false }
            if windows.frontWindow !== window { window.select(); return true }
            trackingDialog = dialog
            deliver(.mouseDown(window.globalToLocal(event.where_)), to: dialog)
            return true
        case 2:
            guard let dialog = trackingDialog, let window = dialog.window else { return false }
            trackingDialog = nil
            deliver(.mouseUp(window.globalToLocal(event.where_)), to: dialog)
            return true
        case 3, 5:
            guard let dialog = dialog(for: windows.frontWindow) else { return false }
            deliver(.key(characters: PascalString(bytes: [UInt8(truncatingIfNeeded: event.message)]),
                         modifiers: Int16(bitPattern: event.modifiers)), to: dialog)
            return true
        default: return false
        }
    }

    /// Route the mouse parameters posted by GraphiteSDLEvents. Key events
    /// require a translated character parameter, not a physical key code.
    @discardableResult
    public func route(_ event: CarbonEvent) -> Bool {
        if event.type.eventClass == "mous", [1, 2, 5].contains(event.type.kind),
           let bytes = event.parameter("mloc", type: "hipt")?.bytes, bytes.count == 8 {
            func word(_ offset: Int) -> UInt32 {
                bytes[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            }
            let x = Float(bitPattern: word(0)), y = Float(bitPattern: word(4))
            guard x.isFinite, y.isFinite, x >= Float(Int16.min), x <= Float(Int16.max),
                  y >= Float(Int16.min), y <= Float(Int16.max) else { return false }
            let point = Point(v: Int16(y.rounded(.towardZero)), h: Int16(x.rounded(.towardZero)))
            if event.type.kind == 5 {
                guard let dialog = trackingDialog, let window = dialog.window else { return false }
                deliver(.mouseMoved(window.globalToLocal(point)), to: dialog)
                return true
            }
            return route(ClassicEvent(what: event.type.kind == 1 ? 1 : 2, location: point))
        }
        if event.type.eventClass == "text", event.type.kind == 1,
           let bytes = event.parameter("text", type: "TEXT")?.bytes, !bytes.isEmpty,
           let dialog = dialog(for: windows.frontWindow) {
            deliver(.key(characters: PascalString(bytes: Array(bytes.prefix(255))), modifiers: 0), to: dialog)
            return true
        }
        if event.type.eventClass == "keyb", [1, 2].contains(event.type.kind),
           let bytes = event.parameter("kchr", type: "char")?.bytes, !bytes.isEmpty,
           let dialog = dialog(for: windows.frontWindow) {
            let modifiers = event.parameter("kmod", type: "magn")?.bytes ?? []
            let flags = modifiers.suffix(2).reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
            deliver(.key(characters: PascalString(bytes: Array(bytes.prefix(255))), modifiers: Int16(bitPattern: flags)), to: dialog)
            return true
        }
        return false
    }
}
