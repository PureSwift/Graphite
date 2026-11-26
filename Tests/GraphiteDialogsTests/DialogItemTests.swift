import Testing
import GraphiteBase
import GraphiteDialogs
import GraphiteWindows
import GraphiteQuickDraw
import GraphiteFiles
import GraphiteResources

private final class TestDialogHost: DialogHost {
    var events: [DialogEvent] = []
    var calls: [String] = []
    func present(_ dialog: Dialog) { calls.append("present") }
    func redraw(_ dialog: Dialog) { calls.append("redraw") }
    func nextEvent(for dialog: Dialog) -> DialogEvent? { events.isEmpty ? nil : events.removeFirst() }
    func dismiss(_ dialog: Dialog) { calls.append("dismiss") }
    func playAlertSound(_ number: Int) { calls.append("sound\(number)") }
}

@Suite struct DialogItemTests {

    @Test func kinds() {
        // The type byte's low seven bits, as the item list keeps them.
        #expect(DialogItemKind.userItem.rawValue == 0)
        #expect(DialogItemKind.helpItem.rawValue == 1)
        #expect(DialogItemKind.button.rawValue == 4)
        #expect(DialogItemKind.checkBox.rawValue == 5)
        #expect(DialogItemKind.radioButton.rawValue == 6)
        #expect(DialogItemKind.control.rawValue == 7)
        #expect(DialogItemKind.staticText.rawValue == 8)
        #expect(DialogItemKind.editText.rawValue == 16)
        #expect(DialogItemKind.icon.rawValue == 32)
        #expect(DialogItemKind.picture.rawValue == 64)
        #expect(DialogItemKind.disableBit == 128)
        // The enable flag is the type byte's high bit, set for disabled.
        let enabled = DialogItemKind.from(typeByte: 4)
        #expect(enabled.kind == .button && enabled.isEnabled)
        let disabled = DialogItemKind.from(typeByte: 4 | 128)
        #expect(disabled.kind == .button && !disabled.isEnabled)
        #expect(DialogItemKind.typeByte(.editText, isEnabled: true) == 16)
        #expect(DialogItemKind.typeByte(.editText, isEnabled: false) == 16 | 128)
        // An unknown type is a user item, as the Dialog Manager's 0 was.
        #expect(DialogItemKind.from(typeByte: 99).kind == .userItem)
        // What each kind keeps.
        #expect(DialogItemKind.button.hasTitle && DialogItemKind.checkBox.hasTitle)
        #expect(DialogItemKind.radioButton.hasTitle && !DialogItemKind.staticText.hasTitle)
        #expect(DialogItemKind.staticText.hasText && DialogItemKind.editText.hasText)
        #expect(!DialogItemKind.icon.hasText)
        #expect(DialogItemKind.control.hasResource && DialogItemKind.icon.hasResource)
        #expect(DialogItemKind.picture.hasResource && !DialogItemKind.button.hasResource)
        #expect(DialogItemKind.userItem.isUserDrawn && !DialogItemKind.button.isUserDrawn)
    }

    @Test func items() {
        let item = DialogItem(bounds: Rect(top: 10, left: 20, bottom: 30, right: 120), kind: .button, text: "OK")
        #expect(item.typeByte == 4)
        #expect(item.isEnabled)
        #expect(item.resourceID == 0)
        #expect(item.contains(Point(v: 20, h: 60)))
        #expect(!item.contains(Point(v: 5, h: 60)))
        // A disabled item's type byte has the bit.
        let disabled = DialogItem(bounds: item.bounds, kind: .button, text: "OK", isEnabled: false)
        #expect(disabled.typeByte == 4 | 128)
    }

    // MARK: 'DITL' resources

    /// A 'DITL' resource's bytes, the way Rez compiled one: the count less
    /// one, and each item — its reserved long, its rectangle, its type
    /// byte, and what its kind keeps.
    private func ditlBytes(_ items: [(rect: Rect, type: UInt8, text: String?, resource: Int16?)]) -> [UInt8] {
        var writer = BigEndianWriter()
        writer.write(UInt16(items.count - 1))
        for item in items {
            writer.write(UInt32(0))
            writer.write(item.rect)
            writer.write(item.type)
            if let text = item.text {
                writer.write(PascalString(text)!)
                writer.align(to: 2)
            } else if let resource = item.resource {
                writer.write(UInt8(0))
                writer.write(resource)
            } else {
                writer.write(UInt8(0))
            }
        }
        return writer.bytes
    }

    @Test func readingItemLists() throws {
        // Two buttons and a line of static text, the simplest dialog.
        let bytes = ditlBytes([
            (Rect(top: 80, left: 20, bottom: 100, right: 90), 4, "OK", nil),
            (Rect(top: 80, left: 110, bottom: 100, right: 180), 4, "Cancel", nil),
            (Rect(top: 10, left: 20, bottom: 60, right: 180), 8, "Save changes before closing?", nil),
        ])
        let list = try DialogItemList(bytes: bytes)
        #expect(list.count == 3)
        #expect(list.items[0].kind == .button && list.items[0].text == "OK")
        #expect(list.items[1].kind == .button && list.items[1].text == "Cancel")
        #expect(list.items[2].kind == .staticText && list.items[2].text == "Save changes before closing?")
        let allEnabled = list.items.allSatisfy { $0.isEnabled }
        #expect(allEnabled)
        #expect(list.item(1)?.text == "OK")
        #expect(list.item(3)?.kind == .staticText)
        // The numbers count from 1; past either end, none.
        #expect(list.item(0) == nil && list.item(4) == nil)
    }

    @Test func readingDisabledAndOtherKinds() throws {
        // A disabled radio button, an editable text, a control by its
        // resource, an icon and a picture.
        let bytes = ditlBytes([
            (Rect(top: 10, left: 10, bottom: 30, right: 110), 6 | 128, "Small", nil),
            (Rect(top: 40, left: 10, bottom: 58, right: 190), 16, "Untitled", nil),
            (Rect(top: 60, left: 10, bottom: 80, right: 190), 7, nil, 128),
            (Rect(top: 90, left: 10, bottom: 122, right: 42), 32, nil, 257),
            (Rect(top: 90, left: 50, bottom: 122, right: 82), 64, nil, 200),
        ])
        let list = try DialogItemList(bytes: bytes)
        #expect(list.count == 5)
        #expect(list.items[0].kind == .radioButton && !list.items[0].isEnabled)
        #expect(list.items[0].text == "Small")
        #expect(list.items[1].kind == .editText && list.items[1].text == "Untitled")
        #expect(list.items[2].kind == .control && list.items[2].resourceID == 128)
        #expect(list.items[3].kind == .icon && list.items[3].resourceID == 257)
        #expect(list.items[4].kind == .picture && list.items[4].resourceID == 200)
    }

    @Test func readingUserAndHelpItems() throws {
        // A user item: a reserved byte after the type byte, no text.
        let user = try DialogItemList(bytes: ditlBytes([
            (Rect(top: 0, left: 0, bottom: 40, right: 40), 0, nil, nil),
        ]))
        #expect(user.items[0].kind == .userItem && user.items[0].text.isEmpty)
        #expect(user.items[0].resourceID == 0)
    }

    @Test func oddLengthTextIsAligned() throws {
        // A title of an odd length has an alignment byte after it, to a
        // word boundary: the next item reads where it should.
        var writer = BigEndianWriter()
        writer.write(UInt16(1))
        writer.write(UInt32(0))
        writer.write(Rect(top: 0, left: 0, bottom: 20, right: 60))
        writer.write(UInt8(4))
        writer.write(PascalString("Yes")) // 1 + 3 bytes: odd, so padded.
        writer.align(to: 2)
        writer.write(UInt32(0))
        writer.write(Rect(top: 0, left: 0, bottom: 20, right: 60))
        writer.write(UInt8(4))
        writer.write(PascalString("No")) // 1 + 2 bytes: even, no padding.
        writer.align(to: 2)
        let list = try DialogItemList(bytes: writer.bytes)
        #expect(list.count == 2)
        #expect(list.items[0].text == "Yes" && list.items[1].text == "No")
    }

    @Test func roundTrips() throws {
        let items = [
            DialogItem(bounds: Rect(top: 80, left: 20, bottom: 100, right: 90), kind: .button, text: "OK"),
            DialogItem(bounds: Rect(top: 10, left: 20, bottom: 60, right: 180), kind: .staticText, text: "Really?"),
            DialogItem(bounds: Rect(top: 40, left: 10, bottom: 58, right: 190), kind: .editText, text: ""),
            DialogItem(bounds: Rect(top: 60, left: 10, bottom: 80, right: 190), kind: .control, resourceID: 128),
            DialogItem(bounds: Rect(top: 0, left: 0, bottom: 20, right: 20), kind: .icon, resourceID: 257),
            DialogItem(bounds: Rect(top: 0, left: 0, bottom: 20, right: 20), kind: .userItem),
            DialogItem(bounds: Rect(top: 0, left: 0, bottom: 20, right: 20), kind: .checkBox, text: "Bold", isEnabled: false),
        ]
        let list = DialogItemList(items: items)
        let read = try DialogItemList(bytes: list.bytes)
        #expect(read.items.map(\.typeByte) == list.items.map(\.typeByte))
        #expect(read.items.map(\.text) == list.items.map(\.text))
        #expect(read.items.map(\.resourceID) == list.items.map(\.resourceID))
    }

    @Test func findingItems() {
        // FindDialogItem numbers from 0, and the first item wins where they
        // overlap.
        var list = DialogItemList()
        list.items = [
            DialogItem(bounds: Rect(top: 0, left: 0, bottom: 40, right: 40), kind: .button, text: "One"),
            DialogItem(bounds: Rect(top: 20, left: 20, bottom: 60, right: 60), kind: .button, text: "Two"),
        ]
        #expect(list.findItem(at: Point(v: 5, h: 5)) == 0)
        #expect(list.findItem(at: Point(v: 50, h: 50)) == 1)
        #expect(list.findItem(at: Point(v: 30, h: 30)) == 0)
        #expect(list.findItem(at: Point(v: 100, h: 100)) == nil)
        #expect(DialogItemList().findItem(at: .zero) == nil)
    }

    @Test func packedAlertStages() throws {
        let bytes: [UInt8] = [0, 1, 0, 2, 0, 40, 0, 80, 0, 128, 0xC9, 0x65, 0, 0]
        let alert = try AlertResource(bytes: bytes)
        #expect(alert.stages.map(\.bits) == [5, 6, 9, 12])
        #expect(alert.stages[0].isDrawn && alert.stages[0].soundCount == 1)
        #expect(alert.stages[2].secondItemIsDefault)
        #expect(alert.bytes == bytes)
        let oldAlert = try AlertResource(bytes: Array(bytes.prefix(12)))
        #expect(oldAlert.position == 0)
    }

    @Test func emptyItemList() throws {
        let list = try DialogItemList(bytes: [0xFF, 0xFF])
        #expect(list.count == 0)
        #expect(list.bytes == [0xFF, 0xFF])
    }

    @Test func windowAndControlLifecycle() throws {
        let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
        let dialog = Dialog(kind: .modal, bounds: Rect(top: 40, left: 40, bottom: 160, right: 300), items: [
            DialogItem(bounds: Rect(top: 80, left: 20, bottom: 100, right: 90), kind: .button, text: "OK")
        ])
        try dialog.attach(to: manager)
        #expect(dialog.window?.isVisible == true)
        #expect(dialog.control(of: 1)?.title == "OK")
        dialog.setText("Save", of: 1)
        #expect(dialog.control(of: 1)?.title == "Save")
        dialog.hide()
        #expect(dialog.window?.isVisible == false)
        dialog.show()
        #expect(manager.frontWindow === dialog.window)
        dialog.dispose()
        #expect(manager.windows.isEmpty)
    }

    @Test func editingAndStandardAlert() {
        let dialog = Dialog(kind: .modal, bounds: Rect(top: 0, left: 0, bottom: 120, right: 300), items: [
            DialogItem(bounds: Rect(top: 10, left: 10, bottom: 30, right: 100), kind: .editText, text: "Old"),
        ])
        dialog.selectText(of: 1)
        _ = dialog.handle(.key(characters: "New", modifiers: 0))
        #expect(dialog.text(of: 1) == "New")
        _ = dialog.handle(.key(characters: "!", modifiers: 0))
        #expect(dialog.text(of: 1) == "New!")
        let alert = StandardAlert(kind: .caution, message: "Save?", cancelText: "Cancel", cancelItem: 2).dialog(bounds: dialog.bounds)
        #expect(alert.item(1)?.bounds.isEmpty == false)
        #expect(alert.item(2)?.bounds.isEmpty == false)
        #expect(alert.cancelHit == 2)
    }

    @Test func loadsControlResource() throws {
        var dlog = BigEndianWriter()
        dlog.write(Rect(top: 40, left: 40, bottom: 160, right: 300))
        dlog.write(Int16(1)); dlog.write(UInt8(1)); dlog.write(UInt8(0))
        dlog.write(UInt8(0)); dlog.write(UInt8(0)); dlog.write(Int32(0)); dlog.write(Int16(128))
        dlog.write(PascalString("")); dlog.align(to: 2); dlog.write(UInt16(0))
        let list = DialogItemList(items: [DialogItem(bounds: .zero, kind: .control, resourceID: 200)])
        var cntl = BigEndianWriter()
        let controlBounds = Rect(top: 10, left: 10, bottom: 30, right: 90)
        cntl.write(controlBounds); cntl.write(Int16(0)); cntl.write(UInt8(1)); cntl.write(UInt8(0))
        cntl.write(Int16(1)); cntl.write(Int16(0)); cntl.write(Int16(0)); cntl.write(Int32(0))
        cntl.write(PascalString("Go"))
        let fork = try ResourceMap.write([
            (Resource(type: "DLOG", id: 100), dlog.bytes),
            (Resource(type: "DITL", id: 128), list.bytes),
            (Resource(type: "CNTL", id: 200), cntl.bytes),
        ])
        let chain = ResourceChain(fileSystem: FileSystem(defaultFolder: "/"))
        try chain.open(bytes: fork)
        let dialog = try Dialog.make(id: 100, resources: chain)
        let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
        try dialog.attach(to: manager)
        #expect(dialog.control(of: 1)?.bounds == controlBounds)
        #expect(dialog.control(of: 1)?.title == "Go")
        #expect(dialog.handle(.mouseDown(Point(v: 15, h: 15))) == nil)
        #expect(dialog.handle(.mouseUp(Point(v: 15, h: 15))) == 1)
    }

    @Test func trackingControls() throws {
        let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
        let dialog = Dialog(kind: .modal, bounds: Rect(top: 40, left: 40, bottom: 160, right: 300), items: [
            DialogItem(bounds: Rect(top: 10, left: 10, bottom: 30, right: 90), kind: .button, text: "OK")
        ])
        try dialog.attach(to: manager)
        #expect(dialog.handle(.mouseDown(Point(v: 15, h: 15))) == nil)
        #expect(dialog.handle(.mouseMoved(Point(v: 50, h: 100))) == nil)
        #expect(dialog.handle(.mouseUp(Point(v: 50, h: 100))) == nil)
        #expect(dialog.handle(.mouseDown(Point(v: 15, h: 15))) == nil)
        #expect(dialog.handle(.mouseUp(Point(v: 15, h: 15))) == 1)
    }

    @Test func alertStagesAndSound() {
        let manager = AlertManager()
        let silent = AlertStage(isDrawn: false, soundCount: 1)
        let shown = AlertStage(isDrawn: true, soundCount: 2)
        let resource = AlertResource(bounds: Rect(top: 0, left: 0, bottom: 100, right: 200), itemListID: 128,
                                     stages: [silent, shown, shown, shown])
        let items = DialogItemList(items: [DialogItem(bounds: .zero, kind: .button, text: "OK")])
        var sounds: [Int] = []
        let first = manager.run(id: 42, resource: resource, items: items, sound: { sounds.append($0) }, next: { nil })
        #expect(first == nil)
        let second = manager.run(id: 42, resource: resource, items: items, sound: { sounds.append($0) }, next: { .key(characters: "\r", modifiers: 0) })
        #expect(second == 1)
        #expect(sounds == [1, 2])
        #expect(manager.counter.stage == 1)
        _ = manager.run(id: 43, resource: resource, items: items, sound: { sounds.append($0) }, next: { nil })
        #expect(manager.counter.stage == 0)
    }

    @Test func hostPresentationAndEditing() {
        let dialog = Dialog(kind: .modal, bounds: Rect(top: 0, left: 0, bottom: 120, right: 240), items: [
            DialogItem(bounds: .zero, kind: .editText, text: "first"),
            DialogItem(bounds: .zero, kind: .editText, text: "second"),
            DialogItem(bounds: .zero, kind: .button, text: "OK")
        ])
        dialog.advanceTextFocus()
        #expect(dialog.keyboardFocus == 1)
        #expect(dialog.copyText() == "first")
        dialog.pasteText("new")
        #expect(dialog.text(of: 1) == "new")
        _ = dialog.handle(.key(characters: "\t", modifiers: 0))
        #expect(dialog.keyboardFocus == 2)
        #expect(dialog.deleteSelection())
        #expect(dialog.text(of: 2) == "")
        dialog.defaultItem = 3
        let host = TestDialogHost()
        host.events = [.key(characters: "\r", modifiers: 0)]
        #expect(dialog.runModal(host: host) == 3)
        #expect(host.calls == ["present", "redraw", "dismiss"])
        #expect(!dialog.isVisible)
    }

    @Test func appendingAndHidingItems() throws {
        let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
        let dialog = Dialog(kind: .modeless, bounds: Rect(top: 40, left: 40, bottom: 140, right: 240), items: [
            DialogItem(bounds: Rect(top: 10, left: 10, bottom: 30, right: 80), kind: .button, text: "One")
        ])
        try dialog.attach(to: manager)
        let list = DialogItemList(items: [DialogItem(bounds: Rect(top: 5, left: 5, bottom: 25, right: 55), kind: .button, text: "Two")])
        try dialog.append(list, at: .right)
        #expect(dialog.count == 2)
        #expect(dialog.itemBounds(2) == Rect(top: 5, left: 205, bottom: 25, right: 255))
        #expect(dialog.window?.contentBounds.right == 295)
        dialog.hideItem(2)
        #expect(dialog.control(of: 2)?.isVisible == false)
        #expect(dialog.hit(at: Point(v: 10, h: 210)) == 0)
        dialog.showItem(2)
        #expect(dialog.control(of: 2)?.isVisible == true)
        try dialog.shorten(by: 1)
        #expect(dialog.count == 1)
        #expect(dialog.window?.contentBounds.right == 295)
    }

    @Test func resourcePositionAndInitialFocus() throws {
        let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
        let dialog = Dialog(kind: .modal, bounds: Rect(top: 0, left: 0, bottom: 100, right: 200), items: [
            DialogItem(bounds: Rect(top: 10, left: 10, bottom: 30, right: 100), kind: .editText, text: "Name")
        ], position: 0x300A)
        try dialog.attach(to: manager)
        #expect(dialog.window?.contentBounds == dialog.bounds)
        #expect(dialog.bounds.left > 0)
        #expect(dialog.keyboardFocus == 1)
        #expect(dialog.selectedText[1] == 4..<4)
    }

    @Test func damagedItemLists() {
        // Cut off inside the count.
        #expect(throws: MacError.parameter) {
            _ = try DialogItemList(bytes: [0])
        }
        // Nothing at all.
        #expect(throws: MacError.parameter) {
            _ = try DialogItemList(bytes: [])
        }
        // Two items said, the first cut off inside its rectangle.
        #expect(throws: MacError.parameter) {
            _ = try DialogItemList(bytes: [0, 1, 0, 0, 0, 0, 0, 10, 0, 20])
        }
        // The text cut off: a length of 5 with 2 bytes there.
        #expect(throws: MacError.parameter) {
            _ = try DialogItemList(bytes: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 5, 79, 75])
        }
    }
}
