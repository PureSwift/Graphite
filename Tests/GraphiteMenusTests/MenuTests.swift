import Testing
import GraphiteBase
import GraphiteMenus

@Suite struct MenuTests {

    // MARK: Constants

    @Test func constants() {
        #expect(MenuItemStyle.bold.rawValue == 1)
        #expect(MenuItemStyle.italic.rawValue == 2)
        #expect(MenuItemStyle.underline.rawValue == 4)
        #expect(MenuItemStyle.outline.rawValue == 8)
        #expect(MenuItemStyle.shadow.rawValue == 16)
        #expect(MenuItemStyle(rawValue: 32) == .condense)
        #expect(MenuItemStyle(rawValue: 64) == .extend)
        #expect(MenuItemStyle(rawValue: 0) == .plain)
        #expect(MenuMark.none.rawValue == 0)
        #expect(MenuMark.checkmark.rawValue == 0x12)
        #expect(MenuMark.diamond.rawValue == 0x13)
        #expect(MenuMark.command.rawValue == 0x11)
        #expect(MenuMark.shift.rawValue == 0x05)
        #expect(MenuMark.option.rawValue == 0x07)
        #expect(MenuMark.escape.rawValue == 0x1B)
        #expect(MenuMark.downArrow.rawValue == 0x6A)
        #expect(MenuMark("√").map(\.rawValue) == 0xC3)
        #expect(MenuMark("€")?.rawValue == 0xDB)
        #expect(MenuKeyModifiers.shift.rawValue == 1)
        #expect(MenuKeyModifiers.option.rawValue == 2)
        #expect(MenuKeyModifiers.control.rawValue == 4)
        #expect(MenuKeyModifiers.noCommand.rawValue == 8)
        #expect(MenuAttributes.excludesMarkColumn.rawValue == 1)
        #expect(MenuAttributes.autoDisable.rawValue == 4)
        #expect(MenuAttributes.hidden.rawValue == 16)
        #expect(MenuAttributes(rawValue: 1 << 5) == .condenseSeparators)
    }

    // MARK: The classic's AppendMenu strings

    @Test func classicItems() {
        // The text alone: an enabled item, plain, with no furniture.
        var item = MenuItem(classic: "About SurfWriter…")
        #expect(item.text == "About SurfWriter…")
        #expect(item.isEnabled && item.mark == .none && item.key == 0 && item.icon == 0)
        #expect(item.style == .plain && item.commandID == FourCharCode(rawValue: 0) && item.submenuID == 0)
        #expect(!item.isSeparator)
        // A hyphen divides.
        item = MenuItem(classic: "-")
        #expect(item.isSeparator && item.text == "-")
        // '(' disables; an item can be a divider and disabled.
        item = MenuItem(classic: "(-")
        #expect(item.isSeparator && !item.isEnabled)
        // '/' names the keyboard equivalent, and ends the item.
        item = MenuItem(classic: "Cut/X")
        #expect(item.text == "Cut" && item.key == UInt8(ascii: "X"))
        // '<' is followed by the style letters B, I, U, O and S, as many as
        // come; they are greedy, so a text that starts with one needs it
        // held back, as an AppendMenu string kept the classic's own.
        item = MenuItem(classic: "<BIUOS")
        #expect(item.style == [.bold, .italic, .underline, .outline, .shadow])
        #expect(item.text.isEmpty)
        item = MenuItem(classic: "<B1234")
        #expect(item.style == [.bold] && item.text == "1234")
        // '!' is followed by a mark, '^' by an icon: the character's MacRoman
        // code is the icon number, as the classic kept it.
        item = MenuItem(classic: "Zürich!√^A")
        #expect(item.text == "Zürich" && item.mark == MenuMark("√") && item.icon == 65)
        // What follows the key equivalent isn't part of the text.
        item = MenuItem(classic: "Bold/B")
        #expect(item.text == "Bold" && item.key == UInt8(ascii: "B"))
        // A blank item, as a string of spaces made: the spaces are its text.
        item = MenuItem(classic: " ")
        #expect(item.text == " " && !item.isSeparator && item.isEnabled)
        // A disabled item with a shift key and a mark.
        item = MenuItem(classic: "(Save As/S")
        #expect(!item.isEnabled && item.text == "Save As" && item.key == UInt8(ascii: "S"))
    }

    @Test func classicSubmenu() {
        // A submenu: $1B for the key, the submenu's menu ID in the mark —
        // the character whose MacRoman byte is the ID.
        let item = MenuItem(classic: "Size!\t/\u{1B}")
        #expect(item.text == "Size")
        #expect(item.submenuID == 9)
        #expect(item.mark == .none)
        #expect(item.key == 0x1B)
        #expect(!item.isSeparator)
    }

    @Test func appendingClassic() {
        let menu = Menu(menuID: 3, title: "Edit")
        menu.append(classic: "Undo/Z;Cut/X;Copy/X;Paste/V;Clear")
        #expect(menu.count == 5)
        #expect(menu.items.map(\.text) == ["Undo", "Cut", "Copy", "Paste", "Clear"])
        #expect(menu.items[2].key == UInt8(ascii: "X"))
        menu.append(classic: "-;Select All/A")
        #expect(menu.count == 7)
        #expect(menu.items[5].isSeparator)
        #expect(menu.items[6].key == UInt8(ascii: "A"))
        // An empty string adds nothing.
        menu.append(classic: "")
        #expect(menu.count == 7)
        // Blank parts between semicolons are blank items.
        menu.append(classic: "One;;Three")
        #expect(menu.items[8].text.isEmpty)
        #expect(menu.items[9].text == "Three")
    }

    // MARK: The menu

    @Test func makingMenus() {
        let menu = Menu(menuID: 128, title: "File")
        #expect(menu.menuID == 128 && menu.title == "File")
        #expect(menu.count == 0 && menu.isEnabled)
        menu.title = "Document"
        #expect(menu.title == "Document")
        let withAttributes = Menu(menuID: 130, title: "Fonts", attributes: [.hidden, .autoDisable])
        #expect(withAttributes.attributes == [.hidden, .autoDisable])
        withAttributes.changeAttributes(add: .excludesMarkColumn, remove: .hidden)
        #expect(withAttributes.attributes == [.autoDisable, .excludesMarkColumn])
    }

    @Test func items() {
        let menu = Menu(menuID: 3, title: "Edit")
        menu.append(MenuItem(text: "Cut", commandID: "cut "))
        menu.append(MenuItem(text: "Copy", commandID: "copy"))
        menu.append(MenuItem(text: "Paste", commandID: "past"))
        #expect(menu.count == 3)
        #expect(menu.items.map(\.text) == ["Cut", "Copy", "Paste"])
        // InsertMenuItem: at an index, the rest pushed down; past the end,
        // at the end.
        menu.insert(MenuItem(text: "Undo", commandID: "undo"), at: 0)
        menu.insert(MenuItem(text: "Clear"), at: 99)
        #expect(menu.items.map(\.text) == ["Undo", "Cut", "Copy", "Paste", "Clear"])
        // DeleteMenuItem.
        menu.remove(at: 1)
        #expect(menu.items.map(\.text) == ["Undo", "Copy", "Paste", "Clear"])
        // DeleteMenuItems.
        menu.remove(in: 1..<3)
        #expect(menu.items.map(\.text) == ["Undo", "Clear"])
        menu.remove(in: 4..<6)
        #expect(menu.count == 2)
        // DeleteAllMenuItems.
        menu.removeAll()
        #expect(menu.count == 0)
        // Change an item whole, and in parts.
        menu.append(MenuItem(text: "Cut"))
        menu[0] = MenuItem(text: "Cutting")
        #expect(menu[0].text == "Cutting")
        menu.setMark(.checkmark, at: 0)
        #expect(menu[0].mark == .checkmark)
        menu.check(true, at: 0)
        #expect(menu[0].mark == .checkmark)
        menu.check(false, at: 0)
        #expect(menu[0].mark == .none)
        menu.setMark(.diamond, at: 0)
        #expect(menu[0].mark == .diamond)
        menu.setEnabled(false, at: 0)
        #expect(!menu.isEnabled(at: 0))
        menu.setEnabled(true, at: 0)
        #expect(menu.isEnabled(at: 0))
        menu.setKeyEquivalent(UInt8(ascii: "X"), modifiers: [.shift, .option], at: 0)
        #expect(menu[0].key == UInt8(ascii: "X"))
        #expect(menu[0].modifiers == [.shift, .option])
    }

    @Test func commands() {
        let menu = Menu(menuID: 129, title: "File")
        menu.append(MenuItem(text: "New", commandID: "new "))
        menu.append(MenuItem(text: "Open…", commandID: "open"))
        menu.append(MenuItem(text: "Save", commandID: "save"))
        menu.append(MenuItem(text: "Divider"))
        #expect(menu.index(ofCommandID: "save") == 2)
        #expect(menu.item(withCommandID: "open")?.text == "Open…")
        #expect(menu.index(ofCommandID: "nope") == nil)
        // A command ID of 0 is no command: it is never found.
        #expect(menu.index(ofCommandID: FourCharCode(rawValue: 0)) == nil)
    }

    @Test func keys() {
        let menu = Menu(menuID: 129, title: "File")
        menu.append(classic: "New/N;Open…/O;Save/S;Save As…/S")
        menu[3].modifiers = [.shift]
        #expect(menu.index(ofKey: UInt8(ascii: "N"), modifiers: []) == 0)
        #expect(menu.index(ofKey: UInt8(ascii: "S"), modifiers: []) == 2)
        #expect(menu.index(ofKey: UInt8(ascii: "S"), modifiers: [.shift]) == 3)
        #expect(menu.index(ofKey: UInt8(ascii: "S"), modifiers: [.option]) == nil)
        #expect(menu.index(ofKey: UInt8(ascii: "Q"), modifiers: []) == nil)
        // A disabled item's key finds nothing.
        menu.setEnabled(false, at: 0)
        #expect(menu.index(ofKey: UInt8(ascii: "N"), modifiers: []) == nil)
    }

    // MARK: 'MENU' resources

    /// A 'MENU' resource's bytes: the ID, the width and height
    /// placeholders, the definition's resource ID, a placeholder, the
    /// enabled flags, the title, and five bytes an item.
    private func menuBytes(id: Int16, enabledFlags: UInt32, title: String,
                           items: [(text: String, icon: UInt8, key: UInt8, mark: UInt8, style: UInt8)]) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes += [UInt8(UInt16(bitPattern: id) >> 8), UInt8(UInt16(bitPattern: id) & 0xFF)]
        bytes += [0, 0, 0, 0, 0, 0, 0, 0] // width, height, definition ID, placeholder
        bytes += [UInt8(enabledFlags >> 24 & 0xFF), UInt8(enabledFlags >> 16 & 0xFF),
                  UInt8(enabledFlags >> 8 & 0xFF), UInt8(enabledFlags & 0xFF)]
        let titleBytes = MacRoman.encode(title)!
        bytes += [UInt8(titleBytes.count)] + titleBytes
        for item in items {
            let textBytes = MacRoman.encode(item.text)!
            bytes += [UInt8(textBytes.count)] + textBytes
            bytes += [item.icon, item.key, item.mark, item.style]
        }
        bytes += [0]
        return bytes
    }

    @Test func readingResources() throws {
        // The Apple menu of the manual's listing — whose Rez bit string
        // reads its low bit first — with the menu enabled, the About item
        // enabled, the divider disabled.
        let bytes = menuBytes(id: 128, enabledFlags: 0xFFFF_FFFB, title: "apple", items: [
            ("About SurfWriter…", 0, 0, 0, 0),
            ("-", 0, 0, 0, 0),
        ])
        let menu = try Menu(bytes: bytes)
        #expect(menu.menuID == 128)
        #expect(menu.title == "apple")
        #expect(menu.isEnabled)
        #expect(menu.count == 2)
        #expect(menu[0].text == "About SurfWriter…" && menu[0].isEnabled)
        #expect(menu[1].isSeparator && !menu[1].isEnabled)
        // An item's furniture: icon, key, mark and style.
        let edit = try Menu(bytes: menuBytes(id: 3, enabledFlags: 1, title: "Edit", items: [
            ("Bold", 1, 66, 18, 1),
        ]))
        #expect(edit[0].icon == 1)
        #expect(edit[0].key == UInt8(ascii: "B"))
        #expect(edit[0].mark == .checkmark)
        #expect(edit[0].style == .bold)
        // Bit 0 the menu's own state: a disabled menu.
        let disabled = try Menu(bytes: menuBytes(id: 4, enabledFlags: 0, title: "Edit", items: [
            ("Cut", 0, 0, 0, 0),
        ]))
        #expect(!disabled.isEnabled)
        #expect(disabled[0].isEnabled == false)
        // Items past the first 31 are enabled, whatever the flags.
        let many = (0..<35).map { ("Item \($0)", UInt8(0), UInt8(0), UInt8(0), UInt8(0)) }
        let long = try Menu(bytes: menuBytes(id: 5, enabledFlags: 0, title: "Long", items: many))
        #expect(long.count == 35)
        #expect(!long[0].isEnabled)
        #expect(!long[30].isEnabled)
        #expect(long[31].isEnabled && long[34].isEnabled)
        // A submenu, kept as the classic kept it: $1B for the key, the
        // menu ID in the mark field.
        let size = try Menu(bytes: menuBytes(id: 6, enabledFlags: 1, title: "Font", items: [
            ("Sizes", 0, 0x1B, 9, 0),
        ]))
        #expect(size[0].submenuID == 9)
        #expect(size[0].mark == .none)
        #expect(size[0].key == 0x1B)
        // An 'mctb' after the items is ignored, as GetMenu ignored one.
        var withExtra = menuBytes(id: 7, enabledFlags: 1, title: "File", items: [
            ("New", 0, 0, 0, 0),
        ])
        withExtra += [0, 128]
        let ignoring = try Menu(bytes: withExtra)
        #expect(ignoring.count == 1 && ignoring[0].text == "New")
    }

    @Test func damagedResources() {
        // Cut off inside the enable flags, before any title.
        #expect(throws: MacError.menuInvalid) {
            _ = try Menu(bytes: [0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
        }
        // Nothing at all.
        #expect(throws: MacError.menuInvalid) {
            _ = try Menu(bytes: [])
        }
        // An item cut off in the middle of its bytes.
        #expect(throws: MacError.menuInvalid) {
            _ = try Menu(bytes: [0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 4, 72, 101, 121])
        }
        // The last item's bytes cut short.
        #expect(throws: MacError.menuInvalid) {
            _ = try Menu(bytes: [0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 72, 101, 121, 0, 0, 0])
        }
    }
}
