import Testing
import GraphiteBase
import GraphiteMenus

@Suite struct MenuBarTests {

    private func makeAppleMenu() -> Menu {
        Menu(menuID: 128, title: "")
    }

    @Test func inserting() {
        let bar = MenuBar()
        #expect(bar.count == 0 && bar.listed.isEmpty)
        let apple = makeAppleMenu()
        let file = Menu(menuID: 129, title: "File")
        let edit = Menu(menuID: 130, title: "Edit")
        // 0, or the ID of no menu there, puts a menu after them all.
        bar.insert(apple, beforeID: 0)
        bar.insert(file, beforeID: 0)
        #expect(bar.menus.map(\.menuID) == [128, 129])
        // Before the menu of an ID.
        bar.insert(edit, beforeID: 129)
        #expect(bar.menus.map(\.menuID) == [128, 130, 129])
        let special = Menu(menuID: 131, title: "Special")
        bar.insert(special, beforeID: 129)
        #expect(bar.menus.map(\.menuID) == [128, 130, 131, 129])
        // A menu already in the list isn't moved.
        bar.insert(file, beforeID: 128)
        #expect(bar.menus.map(\.menuID) == [128, 130, 131, 129])
        #expect(bar.count == 4)
    }

    @Test func hierarchical() {
        let bar = MenuBar()
        let file = Menu(menuID: 129, title: "File")
        bar.insert(file, beforeID: 0)
        // hierMenu: in the list, no title in the bar.
        let sizes = Menu(menuID: 9, title: "Sizes")
        bar.insert(sizes, beforeID: -1)
        #expect(bar.count == 1)
        #expect(bar.hierarchicalMenus.map(\.menuID) == [9])
        #expect(bar.listed.map(\.menuID) == [129, 9])
        // GetMenuHandle finds either kind.
        #expect(bar.menu(id: 129) === file)
        #expect(bar.menu(id: 9) === sizes)
        // A submenu resolves from an item, as the classic's menu list did.
        file.append(classic: "Size!\t/\u{1B}")
        #expect(bar.submenu(of: file[0]) === sizes)
        // An item with no submenu has none; 0 names no menu.
        file.append(MenuItem(text: "Quit"))
        #expect(bar.submenu(of: file[1]) == nil)
        #expect(bar.menu(id: 0) == nil)
    }

    @Test func removing() {
        let bar = MenuBar()
        let apple = makeAppleMenu()
        let file = Menu(menuID: 129, title: "File")
        let sizes = Menu(menuID: 9, title: "Sizes")
        bar.insert(apple, beforeID: 0)
        bar.insert(file, beforeID: 0)
        bar.insert(sizes, beforeID: -1)
        bar.hilite(menuID: 9)
        #expect(bar.hilitedMenuID == 9)
        // DeleteMenu takes it from the bar and the list both.
        bar.remove(menuID: 129)
        #expect(bar.count == 1)
        #expect(bar.listed.map(\.menuID) == [128, 9])
        // A hilite of a menu that's gone unhilites.
        bar.remove(menuID: 9)
        #expect(bar.hilitedMenuID == 0)
        // An ID no menu has does nothing.
        bar.remove(menuID: 999)
        #expect(bar.count == 1)
        // ClearMenuBar: both parts.
        bar.clear()
        #expect(bar.count == 0 && bar.listed.isEmpty)
    }

    @Test func commands() {
        let bar = MenuBar()
        let file = Menu(menuID: 129, title: "File")
        file.append(MenuItem(text: "New", commandID: "new "))
        file.append(MenuItem(text: "Open…", commandID: "open"))
        let edit = Menu(menuID: 130, title: "Edit")
        edit.append(MenuItem(text: "Cut", commandID: "cut "))
        bar.insert(file, beforeID: 0)
        bar.insert(edit, beforeID: 0)
        // GetIndMenuItemWithCommandID searches the bar's menus in order.
        #expect(bar.find(commandID: "open")?.menu === file)
        #expect(bar.find(commandID: "open")?.index == 1)
        #expect(bar.find(commandID: "cut ")?.menu === edit)
        #expect(bar.find(commandID: "nope") == nil)
        // EnableMenuCommand and DisableMenuCommand.
        bar.setEnabled(false, commandID: "cut ")
        #expect(!edit.isEnabled(at: 0))
        #expect(!bar.isEnabled(commandID: "cut "))
        bar.setEnabled(true, commandID: "cut ")
        #expect(bar.isEnabled(commandID: "cut "))
        #expect(!bar.setEnabled(true, commandID: "nope"))
        #expect(!bar.isEnabled(commandID: "nope"))
        // A hidden menu's commands are still found: the attribute is the
        // host's to draw by.
        edit.changeAttributes(add: .hidden)
        #expect(bar.find(commandID: "cut ")?.menu === edit)
    }

    @Test func menuKeys() {
        let bar = MenuBar()
        let file = Menu(menuID: 129, title: "File")
        file.append(classic: "New/N;Open…/O;Save/S")
        let edit = Menu(menuID: 130, title: "Edit")
        edit.append(classic: "Cut/X;Copy/C")
        let sizes = Menu(menuID: 9, title: "Sizes")
        sizes.append(classic: "9/N")
        bar.insert(file, beforeID: 0)
        bar.insert(edit, beforeID: 0)
        bar.insert(sizes, beforeID: -1)
        // MenuKey: the choice, the item numbered from 1.
        #expect(bar.find(key: UInt8(ascii: "N")) == MenuSelection(menuID: 129, itemIndex: 1))
        #expect(bar.find(key: UInt8(ascii: "C")) == MenuSelection(menuID: 130, itemIndex: 2))
        #expect(bar.find(key: UInt8(ascii: "X"))?.menuID == 130)
        // The hierarchical list is searched too, as the classic searched
        // it — even submenus no item used.
        #expect(bar.find(key: UInt8(ascii: "N")) != nil)
        // A disabled item or menu finds nothing.
        edit.setEnabled(false, at: 0)
        #expect(bar.find(key: UInt8(ascii: "X")) == nil)
        edit.isEnabled = false
        #expect(bar.find(key: UInt8(ascii: "C")) == nil)
        // Modifiers are held: shift-S is another item than S.
        file.append(classic: "Save As…/S")
        file[3].modifiers = [.shift]
        #expect(bar.find(key: UInt8(ascii: "S")) == MenuSelection(menuID: 129, itemIndex: 3))
        #expect(bar.find(key: UInt8(ascii: "S"), modifiers: [.shift]) == MenuSelection(menuID: 129, itemIndex: 4))
        #expect(bar.find(key: UInt8(ascii: "S"), modifiers: [.option]) == nil)
        // A key no item has finds nothing.
        #expect(bar.find(key: UInt8(ascii: "Q")) == nil)
    }

    @Test func hiliteAndShow() {
        let bar = MenuBar()
        #expect(bar.isShown)
        let file = Menu(menuID: 129, title: "File")
        bar.insert(file, beforeID: 0)
        bar.hilite(menuID: 129)
        #expect(bar.hilitedMenuID == 129)
        // HiliteMenu(0) unhilites; so does an ID no menu has.
        bar.hilite(menuID: 0)
        #expect(bar.hilitedMenuID == 0)
        bar.hilite(menuID: 129)
        bar.hilite(menuID: 999)
        #expect(bar.hilitedMenuID == 0)
        bar.isShown = false
        #expect(!bar.isShown)
    }

    @Test func changes() {
        let bar = MenuBar()
        var changed = 0
        bar.changeObserver = { _ in changed += 1 }
        bar.insert(makeAppleMenu(), beforeID: 0)
        bar.draw()
        bar.remove(menuID: 128)
        bar.clear()
        #expect(changed == 4)
    }

    @Test func selections() {
        #expect(MenuSelection.none.menuID == 0 && MenuSelection.none.itemIndex == 0)
        #expect(MenuSelection.none.isNone)
        #expect(MenuSelection(menuID: 3, itemIndex: 2) == MenuSelection(menuID: 3, itemIndex: 2))
        #expect(!MenuSelection(menuID: 3, itemIndex: 2).isNone)
    }
}
