// The modal loop: ModalDialog and Alert's work, the Dialog Manager's own
// between an event and the dialog it belongs to. The host brings the
// events — the Event Manager's to come, or its own — as answers to a
// closure the loop calls; the loop runs the filter the program gave it over
// each, or the standard one, which makes Return and Enter a click on the
// default item, and Escape and Command-period one on the cancel item, and
// stops at the item hit.

import GraphiteBase

/// What the host gives the modal loop: an event as it reaches the dialog.
public enum DialogEvent: Hashable, Sendable {

    /// A key pressed, with the characters it makes and the modifiers
    /// held (the Event Manager's bits: Command 256, Shift 512, and so on).
    case key(characters: PascalString, modifiers: Int16)

    /// A mouse-down at a point of the dialog's local coordinates.
    case mouseDown(Point)

    /// Pointer movement and release, in dialog-local coordinates.
    case mouseMoved(Point)
    case mouseUp(Point)

    /// A user item's turn to draw: the host asks the program's procedure.
    /// The loop calls it with the dialog and the item.
    case drawUserItem(item: Int)

    /// The dialog's turn to be activated or deactivated.
    case activate(Bool)

    /// An update event for the dialog: its items drawn again.
    case update
}

/// The platform supplies presentation and a blocking event source. Drawing
/// receives the complete dialog model, including controls and text selection.
public protocol DialogHost: AnyObject {
    func present(_ dialog: Dialog)
    func redraw(_ dialog: Dialog)
    func nextEvent(for dialog: Dialog) -> DialogEvent?
    func dismiss(_ dialog: Dialog)
    func playAlertSound(_ number: Int)
    func configureStandardAlert(_ alert: StandardAlert, dialog: Dialog)
}

public extension DialogHost {
    func configureStandardAlert(_ alert: StandardAlert, dialog: Dialog) {}
}

/// An event filter (ModalFilterProc): it takes an event and answers whether
/// it handled it. When it has, the loop returns the item it says was hit.
public typealias DialogFilter = @Sendable (_ dialog: Dialog, _ event: DialogEvent, _ itemHit: inout Int) -> Bool

/// The standard event filter, as the Dialog Manager's own: Return and Enter
/// are a click on the default item, Escape and Command-period one on the
/// cancel item — where the dialog has them. It handles no other event.
public struct StandardDialogFilter: Sendable {

    public init() {}

    public func filter(_ dialog: Dialog, _ event: DialogEvent, _ itemHit: inout Int) -> Bool {
        switch event {
        case .key(let characters, let modifiers):
            // Return and Enter, without the Command key.
            if characters.bytes.first == 0x0D || characters.bytes.first == 0x03, modifiers & 0x0100 == 0 {
                itemHit = dialog.defaultHit
                return dialog.defaultHit != 0
            }
            // Escape, or Command-period: the cancel item.
            let isEscape = characters.bytes.first == 0x1B
            let isCommandPeriod = characters.bytes.first == UInt8(ascii: ".") && modifiers & 0x0100 != 0
            if isEscape || isCommandPeriod {
                itemHit = dialog.cancelHit
                return dialog.cancelHit != 0
            }
            return false
        default:
            return false
        }
    }
}

public extension Dialog {

    /// Process an event for a modal or modeless dialog. An item number is
    /// returned when the event is reported to the application.
    func handle(_ event: DialogEvent) -> Int? {
        switch event {
        case .mouseDown(let point):
            let controlHit = controlList.findControl(at: point).flatMap { found in
                controls.first { $0.value === found.control }?.key
            }
            let number = controlHit ?? hit(at: point)
            guard let item = item(number), item.isEnabled else { return nil }
            if item.kind == .editText {
                focusTextItem(number)
                return nil
            }
            if let control = control(of: number) {
                guard control.isLive else { return nil }
                let part = control.hitTest(point)
                guard part != .none, part != .disabled else { return nil }
                trackingItem = number
                control.hilite(part)
                return nil
            }
            return number
        case .mouseMoved(let point):
            if let number = trackingItem, let control = control(of: number) {
                let part = control.hitTest(point)
                control.hilite(part == .disabled ? .none : part)
            }
        case .mouseUp(let point):
            guard let number = trackingItem else { return nil }
            trackingItem = nil
            guard let control = control(of: number) else { return nil }
            let part = control.hitTest(point)
            control.hilite(.none)
            guard control.isLive, part != .none, part != .disabled else { return nil }
            return number
        case .drawUserItem(let number):
            item(number)?.drawProcedure?(self, number)
        case .key(let characters, let modifiers):
            if characters.bytes.first == 0x09, modifiers & 0x0100 == 0 {
                advanceTextFocus(backwards: modifiers & 0x0200 != 0)
                return nil
            }
            guard modifiers & 0x0100 == 0, let number = keyboardFocus,
                  let item = item(number), item.kind == .editText, item.isEnabled else { return nil }
            var bytes = item.text.bytes
            let count = bytes.count
            let selection = selectedText[number] ?? count..<count
            let lower = min(max(selection.lowerBound, 0), count)
            let upper = min(max(selection.upperBound, lower), count)
            var start = lower
            let input = characters.bytes
            if input.first == 0x1C || input.first == 0x1D {
                let position: Int
                if input.first == 0x1C {
                    position = lower == upper ? max(0, lower - 1) : lower
                } else {
                    position = lower == upper ? min(count, upper + 1) : upper
                }
                selectedText[number] = position..<position
                return nil
            }
            if input.first == 0x08 || input.first == 0x7F {
                if start == upper && start > 0 { start -= 1 }
                bytes.removeSubrange(start..<upper)
            } else if input.allSatisfy({ $0 >= 0x20 }) {
                bytes.replaceSubrange(start..<upper, with: input.prefix(255 - (count - (upper - start))))
                start += min(input.count, 255 - (count - (upper - start)))
            } else { return nil }
            setText(PascalString(bytes: bytes), of: number)
            selectedText[number] = start..<start
        case .activate(let active):
            for control in controls.values { if active { control.activate() } else { control.deactivate() } }
        case .update:
            for (index, item) in itemList.items.enumerated() where item.kind == .userItem {
                item.drawProcedure?(self, index + 1)
            }
        }
        return nil
    }

    /// Present and run using the host's event source. A nil event ends the
    /// session, allowing a host to report shutdown without busy waiting.
    func runModal(host: any DialogHost, filter: DialogFilter? = nil) -> Int {
        show()
        host.present(self)
        host.redraw(self)
        defer { host.dismiss(self); hide() }
        let effectiveFilter = filter ?? StandardDialogFilter().filter
        var itemHit = 0
        while let event = host.nextEvent(for: self) {
            if effectiveFilter(self, event, &itemHit) { return itemHit }
            let hit = handle(event)
            host.redraw(self)
            if let hit, hit != 0 { return hit }
        }
        return 0
    }

    /// ModalDialog: the item the user hit, as the dialog's filter sees the
    /// host's events. `next` gives the events until it answers nil; with
    /// none left, the loop returns 0 — the host has stopped giving events,
    /// as a closed window would.
    func runModal(next: () -> DialogEvent?, filter: DialogFilter? = nil) -> Int {
        let filter = filter ?? StandardDialogFilter().filter
        var itemHit = 0
        while let event = next() {
            // The filter first, as the Dialog Manager's ran before its own
            // handling.
            if filter(self, event, &itemHit) { return itemHit }
            if let hit = handle(event), hit != 0 { return hit }
        }
        return 0
    }
}
