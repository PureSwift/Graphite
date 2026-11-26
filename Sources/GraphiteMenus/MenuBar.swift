// The menu bar: the menus across it, left to right, and the menus held in
// the menu list without a title in the bar — the submenus and pop-up menus
// InsertMenu keeps with hierMenu. InsertMenu puts one before another by
// menu ID, or after them all; DeleteMenu takes one out by its ID;
// GetMenuHandle finds one of either kind. MenuKey looks through them all
// for a keyboard equivalent. The host draws the bar — DrawMenuBar and
// InvalMenuBar tell it the bar changed — and tracks the choices, which
// MenuSelect answers as a menu ID and an item's number.

import GraphiteBase

/// What a menu choice was: the menu's ID and the item chosen, numbered
/// from 1 as MenuSelect and MenuChoice answered (0 for none).
public struct MenuSelection: Hashable, Sendable {

    public var menuID: Int16

    /// The item's number, from 1; 0 for no choice.
    public var itemIndex: Int16

    public init(menuID: Int16, itemIndex: Int16) {
        self.menuID = menuID
        self.itemIndex = itemIndex
    }

    /// MenuSelect's answer when nothing was chosen.
    public static var none: MenuSelection { MenuSelection(menuID: 0, itemIndex: 0) }

    public var isNone: Bool { menuID == 0 && itemIndex == 0 }
}

public final class MenuBar {

    /// The menus across the bar, left to right.
    public private(set) var menus: [Menu]

    /// The menus InsertMenu keeps with hierMenu (-1): in the menu list,
    /// for MenuKey to find and submenus to resolve, with no title in the
    /// bar.
    public private(set) var hierarchicalMenus: [Menu]

    /// ShowMenuBar and HideMenuBar; a bar nobody sees draws nothing, but
    /// MenuKey finds its items as ever.
    public var isShown = true

    /// The menu HiliteMenu named, 0 for none. HiliteMenu(0) unhilites.
    public internal(set) var hilitedMenuID: Int16 = 0

    /// DrawMenuBar and InvalMenuBar: the bar changed, and the host draws
    /// it again.
    public var changeObserver: ((MenuBar) -> Void)?

    public init() {
        menus = []
        hierarchicalMenus = []
    }

    /// How many menus are across the bar.
    public var count: Int { menus.count }

    /// The menus in the list, bar first then hierarchical, as GetMenuHandle
    /// and MenuKey look through them.
    public var listed: [Menu] { menus + hierarchicalMenus }

    // MARK: Inserting and removing

    /// InsertMenu: a menu before the menu of `beforeID`'s ID; 0, or the ID
    /// of no menu in the list, puts it after them all; -1 (hierMenu) keeps
    /// it in the list without a title in the bar. A menu already in the
    /// list isn't moved.
    public func insert(_ menu: Menu, beforeID: Int16) {
        guard !listed.contains(where: { $0 === menu }) else { return }
        if beforeID == -1 {
            hierarchicalMenus.append(menu)
        } else if let index = menus.firstIndex(where: { $0.menuID == beforeID }) {
            menus.insert(menu, at: index)
        } else {
            menus.append(menu)
        }
        changed()
    }

    /// DeleteMenu: the menu of the ID is gone from the bar and the
    /// hierarchical list both. A menu of no ID that is there does nothing.
    public func remove(menuID: Int16) {
        menus.removeAll { $0.menuID == menuID }
        hierarchicalMenus.removeAll { $0.menuID == menuID }
        if hilitedMenuID == menuID { hilitedMenuID = 0 }
        changed()
    }

    /// ClearMenuBar: every menu, in the bar and in the list.
    public func clear() {
        menus.removeAll()
        hierarchicalMenus.removeAll()
        hilitedMenuID = 0
        changed()
    }

    // MARK: Finding

    /// GetMenuHandle: the menu of an ID, in the bar or the hierarchical
    /// list.
    public func menu(id: Int16) -> Menu? {
        listed.first { $0.menuID == id }
    }

    /// The menu an item's submenu ID names, as the classic's menu list
    /// resolved a submenu: in the bar or the hierarchical list.
    public func submenu(of item: MenuItem) -> Menu? {
        item.submenuID == 0 ? nil : menu(id: item.submenuID)
    }

    /// GetIndMenuItemWithCommandID: the first item of the command ID in
    /// any menu in the list, with its menu.
    public func find(commandID: FourCharCode) -> (menu: Menu, index: Int)? {
        for menu in listed {
            if let index = menu.index(ofCommandID: commandID) {
                return (menu, index)
            }
        }
        return nil
    }

    /// EnableMenuCommand and DisableMenuCommand: the item of the command
    /// ID, in any menu in the list. Returns false when there is none.
    @discardableResult
    public func setEnabled(_ enabled: Bool, commandID: FourCharCode) -> Bool {
        guard let found = find(commandID: commandID) else { return false }
        found.menu.setEnabled(enabled, at: found.index)
        return true
    }

    /// IsMenuCommandEnabled: the item of the command ID, and its state;
    /// false when there is none.
    public func isEnabled(commandID: FourCharCode) -> Bool {
        guard let found = find(commandID: commandID) else { return false }
        return found.menu.isEnabled(at: found.index)
    }

    /// MenuKey: the choice an enabled item's keyboard equivalent makes,
    /// in the bar's menus and the hierarchical list alike — the classic
    /// searched them all, even submenus no item used. The item's
    /// modifiers are what the search holds; the Command key is implied
    /// unless the item says noCommand.
    public func find(key: UInt8, modifiers: MenuKeyModifiers = .none) -> MenuSelection? {
        for menu in listed where menu.isEnabled {
            if let index = menu.index(ofKey: key, modifiers: modifiers) {
                return MenuSelection(menuID: menu.menuID, itemIndex: Int16(index + 1))
            }
        }
        return nil
    }

    /// HiliteMenu: the menu of the ID is drawn hilited in the bar; 0
    /// unhilites. An ID no menu has unhilites too.
    public func hilite(menuID: Int16) {
        hilitedMenuID = menuID == 0 || listed.contains { $0.menuID == menuID } ? menuID : 0
    }

    // MARK: The bar the host draws

    /// DrawMenuBar and InvalMenuBar: the bar changed.
    public func draw() {
        changeObserver?(self)
    }

    /// ShowMenuBar and HideMenuBar's work.
    private func changed() {
        changeObserver?(self)
    }
}
