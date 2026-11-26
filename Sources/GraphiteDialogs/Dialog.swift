// A dialog box: a window of one of the Dialog Manager's own kinds — modal,
// movable modal or modeless — holding an item list. The items are found,
// hit-tested and have their text read and changed by the number the
// Dialog Manager gave them; the default item and the cancel item are set,
// for the Return and Escape keys to choose; and ParamText's strings are
// substituted into the static text, as the Dialog Manager wrote ^0 through
// ^3 into it. The host draws the box and its items, and tracks the controls
// in it.

import GraphiteBase
import GraphiteWindows
import GraphiteControls

/// The kind of dialog box a 'DLOG' resource's window definition ID names
/// (dBoxProc, noGrowDocProc and movableDBoxProc).
public enum DialogKind: Hashable, Sendable {

    /// dBoxProc: a modal dialog box, fixed in place.
    case modal
    /// noGrowDocProc: a modeless dialog box, with a title bar.
    case modeless
    /// movableDBoxProc: a movable modal dialog box.
    case movableModal

    /// The window definition ID.
    public var definitionID: Int16 {
        switch self {
        case .modal: return 1
        case .modeless: return 4
        case .movableModal: return 5
        }
    }

    /// The kind of a window definition ID, as the Dialog Manager read it.
    public init?(definitionID: Int16) {
        switch definitionID {
        case 1: self = .modal
        case 4: self = .modeless
        case 5: self = .movableModal
        default: return nil
        }
    }
}

public final class Dialog {

    /// The window definition the dialog was made with.
    public let kind: DialogKind

    /// The backing window, once attached to a Window Manager.
    public private(set) var window: Window?

    /// Controls corresponding to the dialog's control items, keyed by item number.
    public private(set) var controls: [Int: Control] = [:]
    public let controlList = ControlList()

    // Resource bytes are retained so rebuilding a list can recreate CNTL items.
    var controlResources: [Int16: [UInt8]] = [:]
    var trackingItem: Int?
    private var instantiatedResourceIDs: [Int: Int16] = [:]

    /// Attach the dialog to a window manager. The host presents the window
    /// and the controls and forwards input through the dialog event API.
    public func attach(to manager: WindowManager) throws(MacError) {
        guard window == nil else { throw .parameter }
        let windowClass: WindowClass
        switch kind {
        case .modal: windowClass = .modal
        case .movableModal: windowClass = .movableModal
        case .modeless: windowClass = .document
        }
        let parent = manager.frontWindow
        let window = try manager.newWindow(windowClass: windowClass,
                                           attributes: hasCloseBox ? [.closeBox] : [],
                                           bounds: bounds, title: title)
        window.kindCode = 2
        window.referenceConstant = UInt(UInt32(bitPattern: reference))
        let placement: WindowPositionMethod?
        switch position {
        case 0x300A: placement = .alertPositionOnMainScreen
        case 0x700A: placement = parent == nil ? .alertPositionOnMainScreen : .alertPositionOnParentWindowScreen
        case 0xB00A: placement = parent == nil ? .alertPositionOnMainScreen : .alertPositionOnParentWindow
        default: placement = nil
        }
        if let placement {
            do {
                try manager.reposition(window, method: placement, relativeTo: parent)
                bounds = window.contentBounds
            } catch {
                window.dispose()
                throw error
            }
        }
        self.window = window
        rebuildControls()
        if keyboardFocus == nil, let index = itemList.items.firstIndex(where: { $0.kind == .editText && $0.isEnabled }) {
            focusTextItem(index + 1)
        }
        if isVisible { window.show() }
    }

    private func rebuildControls() {
        let previous = controls
        let previousResourceIDs = instantiatedResourceIDs
        controls = [:]
        instantiatedResourceIDs = [:]
        for control in previous.values { controlList.remove(control) }
        for (index, item) in itemList.items.enumerated() {
            let number = index + 1
            if item.kind == .control {
                let control: Control?
                if previousResourceIDs[number] == item.resourceID {
                    control = previous[number]
                } else if let bytes = controlResources[item.resourceID] {
                    control = try? Control.make(bytes: bytes)
                } else {
                    control = nil
                }
                if let control {
                    if item.isEnabled { control.enable() } else { control.disable() }
                    if hiddenItems.contains(number) { control.hide() }
                    controls[number] = control
                    instantiatedResourceIDs[number] = item.resourceID
                    controlList.add(control)
                }
                continue
            }
            let kind: ControlKind
            switch item.kind {
            case .button: kind = .button
            case .checkBox: kind = .checkBox
            case .radioButton: kind = .radioButton
            default: continue
            }
            let control: Control
            if let existing = previous[index + 1], existing.kind == kind, existing.bounds == item.bounds {
                control = existing
                control.title = item.text
            } else {
                control = Control(kind: kind, bounds: item.bounds, title: item.text)
            }
            if item.isEnabled { control.enable() } else { control.disable() }
            if hiddenItems.contains(number) { control.hide() } else { control.show() }
            controls[index + 1] = control
            controlList.add(control)
        }
    }

    public func control(of number: Int) -> Control? { controls[number] }

    public func dispose() {
        window?.dispose()
        window = nil
        for control in controls.values { controlList.remove(control) }
        controls.removeAll()
        isVisible = false
    }

    /// The dialog's rectangle, in global coordinates: where the box goes
    /// on the screen.
    public internal(set) var bounds: Rect

    /// SetWTitle and GetWTitle: shown in the title bar of a modeless
    /// dialog alone.
    public var title: PascalString

    /// The window's reference constant.
    public var reference: Int32

    /// Whether a close box is drawn: a modeless dialog's, as goAway asked.
    public let hasCloseBox: Bool

    /// The positioning constant of the 'DLOG' or 'ALRT' resource, 0 for
    /// none.
    public let position: UInt16

    /// The items, in their order.
    public var itemList: DialogItemList {
        didSet { if window != nil { rebuildControls() } }
    }

    /// The resource ID of the 'DITL' the dialog was made from; 0 for one
    /// made item by item.
    public internal(set) var itemListID: Int16 = 0

    /// SetDialogDefaultItem: the item Return and Enter choose, as a click
    /// on it. 0 is none. The Dialog Manager draws the default button with a
    /// bold outline.
    public var defaultItem: Int = 0

    /// SetDialogCancelItem: the item Escape and Command-period choose. 0 is
    /// none.
    public var cancelItem: Int = 0

    /// ParamText's strings, substituted for ^0 through ^3 in the items'
    /// text as it is drawn.
    public private(set) var paramText: [PascalString] = ["", "", "", ""]

    /// Whether the dialog is shown.
    public internal(set) var isVisible = true

    public init(kind: DialogKind, bounds: Rect, title: PascalString = "", items: [DialogItem] = [],
                reference: Int32 = 0, hasCloseBox: Bool = false, position: UInt16 = 0) {
        self.kind = kind
        self.bounds = bounds
        self.title = title
        self.itemList = DialogItemList(items: items)
        self.reference = reference
        self.hasCloseBox = hasCloseBox
        self.position = position
    }

    /// How a list appended to a dialog is positioned.
    public enum AppendPosition: Sendable {
        case overlay, right, bottom, relativeToItem(Int)
    }

    /// AppendDITL. Right and bottom placements expand the content bounds;
    /// relative placement uses the selected item's upper-left corner.
    public func append(_ list: DialogItemList, at position: AppendPosition = .overlay) throws(MacError) {
        let width = bounds.width, height = bounds.height
        let offsetH: Int
        let offsetV: Int
        switch position {
        case .overlay: offsetH = 0; offsetV = 0
        case .right: offsetH = width; offsetV = 0
        case .bottom: offsetH = 0; offsetV = height
        case .relativeToItem(let number):
            guard let anchor = item(number) else { throw .parameter }
            offsetH = Int(anchor.bounds.left); offsetV = Int(anchor.bounds.top)
        }
        var additions: [DialogItem] = []
        for var entry in list.items {
            let top = Int(entry.bounds.top) + offsetV, bottom = Int(entry.bounds.bottom) + offsetV
            let left = Int(entry.bounds.left) + offsetH, right = Int(entry.bounds.right) + offsetH
            guard let t = Int16(exactly: top), let b = Int16(exactly: bottom),
                  let l = Int16(exactly: left), let r = Int16(exactly: right) else { throw .parameter }
            entry.bounds = Rect(top: t, left: l, bottom: b, right: r)
            additions.append(entry)
        }
        var newBounds = bounds
        if case .right = position {
            let right = max(width, additions.map { Int($0.bounds.right) }.max() ?? width) + Int(bounds.left)
            guard let value = Int16(exactly: right) else { throw .parameter }
            newBounds.right = value
        }
        if case .bottom = position {
            let bottom = max(height, additions.map { Int($0.bounds.bottom) }.max() ?? height) + Int(bounds.top)
            guard let value = Int16(exactly: bottom) else { throw .parameter }
            newBounds.bottom = value
        }
        if newBounds != bounds {
            try window?.setBounds(newBounds, region: .content)
            bounds = newBounds
        }
        itemList.items.append(contentsOf: additions)
    }

    /// ShortenDITL removes items from the end without resizing the window.
    public func shorten(by number: Int) throws(MacError) {
        guard number >= 0, number <= count else { throw .parameter }
        itemList.items.removeLast(number)
        selectedText = selectedText.filter { $0.key <= count }
        if let focus = keyboardFocus, focus > count { keyboardFocus = nil }
        if defaultItem > count { defaultItem = 0 }
        if cancelItem > count { cancelItem = 0 }
    }

    /// CountDITL.
    public var count: Int { itemList.count }

    /// GetDialogItem: the item of a number, counted from 1; nil for a
    /// number no item has.
    public func item(_ number: Int) -> DialogItem? {
        itemList.item(number)
    }

    /// SetDialogItem: the item of a number is replaced. A number no item
    /// has changes nothing.
    public func setItem(_ number: Int, to item: DialogItem) {
        guard number >= 1, number <= itemList.items.count else { return }
        itemList.items[number - 1] = item
    }

    /// Hidden item numbers. Hidden items retain their original rectangles.
    public private(set) var hiddenItems: Set<Int> = []

    public func hideItem(_ number: Int) {
        guard item(number) != nil else { return }
        hiddenItems.insert(number)
        control(of: number)?.hide()
        if keyboardFocus == number { keyboardFocus = nil }
    }

    public func showItem(_ number: Int) {
        guard item(number) != nil else { return }
        hiddenItems.remove(number)
        control(of: number)?.show()
    }

    /// The item's display rectangle, in the dialog's local coordinates.
    public func itemBounds(_ number: Int) -> Rect? {
        item(number)?.bounds
    }

    /// FindDialogItem: the item a point of the dialog's local coordinates
    /// is in, numbered from 0, the first when items overlap; nil for a
    /// point in none.
    public func findItem(at point: Point) -> Int? {
        itemList.items.enumerated().first { !hiddenItems.contains($0.offset + 1) && $0.element.contains(point) }?.offset
    }

    // MARK: Text

    /// GetDialogItemText and SetDialogItemText, for an item that keeps
    /// text; a number no item has, or an item without text, changes
    /// nothing.
    public func text(of number: Int) -> PascalString? {
        guard let item = item(number), item.kind.hasText else { return nil }
        return item.text
    }

    public func setText(_ text: PascalString, of number: Int) {
        guard number >= 1, number <= itemList.items.count, itemList.items[number - 1].kind.hasText else { return }
        itemList.items[number - 1].text = text
    }

    /// SelectDialogItemText: the range of an editable text item's text
    /// that is selected. The host draws the selection.
    public func selectText(of number: Int, range: Range<Int>? = nil) {
        guard number >= 1, number <= itemList.items.count, itemList.items[number - 1].kind == .editText else { return }
        let count = itemList.items[number - 1].text.count
        let selection = range ?? 0..<count
        let lower = min(max(selection.lowerBound, 0), count)
        let upper = min(max(selection.upperBound, lower), count)
        selectedText[number] = lower..<upper
        keyboardFocus = number
    }

    /// The selected ranges of the editable text items, by item number.
    public internal(set) var selectedText: [Int: Range<Int>] = [:]

    /// An item's text as it is drawn: the ParamText strings in place of
    /// their ^0 through ^3.
    public func drawnText(of number: Int) -> PascalString? {
        guard let text = text(of: number) else { return nil }
        guard item(number)?.kind == .staticText else { return text }
        var result: [UInt8] = []
        var index = text.bytes.startIndex
        while index < text.bytes.endIndex {
            if text.bytes[index] == UInt8(ascii: "^"), index + 1 < text.bytes.endIndex,
               (48...51).contains(text.bytes[index + 1]) {
                result.append(contentsOf: paramText[Int(text.bytes[index + 1] - 48)].bytes)
                index += 2
            } else {
                result.append(text.bytes[index])
                index += 1
            }
        }
        return PascalString(bytes: result)
    }

    /// ParamText: the four strings.
    public func setParamText(_ p0: PascalString, _ p1: PascalString, _ p2: PascalString, _ p3: PascalString) {
        paramText = [p0, p1, p2, p3]
    }

    // MARK: Hits

    /// The item a mouse-down in the dialog's local coordinates is in, as
    /// ModalDialog and DialogSelect report it — the item's number from 1,
    /// for an enabled item; 0 for none, or a disabled one.
    public func hit(at point: Point) -> Int {
        guard let index = findItem(at: point), itemList.items[index].isEnabled else { return 0 }
        return index + 1
    }

    /// Whether an item is enabled: only enabled items report their hits.
    public func isItemEnabled(_ number: Int) -> Bool {
        !hiddenItems.contains(number) && (item(number)?.isEnabled ?? false)
    }

    /// The default and cancel items as clicks on them: the standard event
    /// filter's answers to Return and Enter, and to Escape and
    /// Command-period. 0 where none is set.
    public var defaultHit: Int { isItemEnabled(defaultItem) ? defaultItem : 0 }
    public var cancelHit: Int { isItemEnabled(cancelItem) ? cancelItem : 0 }

    /// The editable item receiving keyboard input, if any.
    public internal(set) var keyboardFocus: Int?

    /// Move keyboard focus through enabled editable items, wrapping at either end.
    public func advanceTextFocus(backwards: Bool = false) {
        let fields = itemList.items.enumerated().compactMap { index, item in
            item.kind == .editText && item.isEnabled ? index + 1 : nil
        }
        guard !fields.isEmpty else { keyboardFocus = nil; return }
        let current = keyboardFocus.flatMap { fields.firstIndex(of: $0) }
        let index: Int
        if let current {
            index = (current + (backwards ? fields.count - 1 : 1)) % fields.count
        } else {
            index = backwards ? fields.count - 1 : 0
        }
        selectText(of: fields[index])
    }

    /// Copy or delete the selection in the focused editable item. The caller
    /// owns the scrap and may pass its contents back to `pasteText`.
    public func copyText() -> PascalString? {
        guard let number = keyboardFocus, let item = item(number), item.kind == .editText else { return nil }
        let count = item.text.count
        let selection = selectedText[number] ?? count..<count
        let lower = min(max(selection.lowerBound, 0), count)
        let upper = min(max(selection.upperBound, lower), count)
        return PascalString(bytes: Array(item.text.bytes[lower..<upper]))
    }

    @discardableResult
    public func deleteSelection() -> Bool {
        guard let number = keyboardFocus, let item = item(number), item.kind == .editText, item.isEnabled else { return false }
        let count = item.text.count
        let selection = selectedText[number] ?? count..<count
        let lower = min(max(selection.lowerBound, 0), count)
        let upper = min(max(selection.upperBound, lower), count)
        guard lower < upper else { return false }
        var bytes = item.text.bytes
        bytes.removeSubrange(lower..<upper)
        setText(PascalString(bytes: bytes), of: number)
        selectedText[number] = lower..<lower
        return true
    }

    public func pasteText(_ text: PascalString) {
        guard let number = keyboardFocus, let item = item(number), item.kind == .editText, item.isEnabled else { return }
        let count = item.text.count
        let selection = selectedText[number] ?? count..<count
        let lower = min(max(selection.lowerBound, 0), count)
        let upper = min(max(selection.upperBound, lower), count)
        let inserted = Array(text.bytes.prefix(255 - (count - (upper - lower))))
        var bytes = item.text.bytes
        bytes.replaceSubrange(lower..<upper, with: inserted)
        setText(PascalString(bytes: bytes), of: number)
        selectedText[number] = (lower + inserted.count)..<(lower + inserted.count)
    }

    public func focusTextItem(_ number: Int) {
        guard let item = item(number), item.kind == .editText, item.isEnabled else { return }
        keyboardFocus = number
        if selectedText[number] == nil { selectedText[number] = item.text.count..<item.text.count }
    }

    // MARK: Showing

    /// ShowWindow and HideWindow's work for the dialog.
    public func show() { isVisible = true; window?.show() }
    public func hide() { isVisible = false; window?.hide() }
}
