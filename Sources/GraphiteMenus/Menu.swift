// A menu: its title, its menu ID, and its items, with the calls the classic
// made of them — AppendMenu's metacharacter string, CheckMenuItem's mark,
// EnableMenuItem, the keyboard equivalents MenuKey finds, and the command
// IDs Carbon gave items. NewMenu makes one; CreateNewWindow's generation,
// CreateNewMenu, takes attributes too. The host draws it; the definition
// gives the sizes.

import GraphiteBase

public final class Menu {

    /// The menu's ID, as NewMenu takes it and the classic's menu list
    /// knows it by: positive for an application's, negative for a desk
    /// accessory's, 0 Apple's own. Submenus are 1 through 255.
    public let menuID: Int16

    /// SetMenuTitle and GetMenuTitle.
    public var title: PascalString

    /// The attributes CreateNewMenu takes; ChangeMenuAttributes changes.
    public private(set) var attributes: MenuAttributes

    /// The shape of the menu and its items, for the host that draws them.
    public let definition: any MenuDefinition

    /// The menu's items, top to bottom. Items are numbered from 0, as an
    /// array's are; the classic numbered them from 1, which is the layer
    /// that exports Carbon's business.
    public private(set) var items: [MenuItem]

    /// The menu's own enabled state — the enable flags' bit 0. A disabled
    /// menu's items draw dimmed, whatever their own states.
    public var isEnabled = true

    /// NewMenu, and CreateNewMenu with its attributes.
    public init(menuID: Int16, title: PascalString, attributes: MenuAttributes = [],
                definition: (any MenuDefinition)? = nil) {
        self.menuID = menuID
        self.title = title
        self.attributes = attributes
        self.definition = definition ?? StandardMenuDefinition()
        items = []
    }

    /// CountMenuItems.
    public var count: Int { items.count }

    // MARK: Items

    /// AppendMenuItemText: an item at the end.
    public func append(_ item: MenuItem) {
        items.append(item)
    }

    /// AppendMenu: one item for every semicolon-separated part of the
    /// string, each read as the classic's metacharacters made it. Blank
    /// parts make blank items, as the classic's did; an empty string
    /// makes none.
    public func append(classic data: String) {
        for part in splitItems(data) {
            append(MenuItem(classic: part))
        }
    }

    /// InsertMenuItem: an item at an index, the rest pushed down.
    public func insert(_ item: MenuItem, at index: Int) {
        let index = min(max(0, index), items.count)
        items.insert(item, at: index)
    }

    /// DeleteMenuItem.
    public func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
    }

    /// DeleteMenuItems.
    public func remove(in range: Range<Int>) {
        let range = range.clamped(to: items.indices)
        guard !range.isEmpty else { return }
        items.removeSubrange(range)
    }

    /// DeleteAllMenuItems.
    public func removeAll() {
        items.removeAll()
    }

    /// GetMenuItemText, and SetMenuItemText, SetItemMark, SetItemIcon,
    /// SetItemStyle, SetItemCmd: reading an item, and changing it, whole.
    public subscript(index: Int) -> MenuItem {
        get { items[index] }
        set { items[index] = newValue }
    }

    /// GetIndMenuItemWithCommandID, this menu alone: the first item of the
    /// command ID, nil if there is none.
    public func index(ofCommandID commandID: FourCharCode) -> Int? {
        items.firstIndex { $0.commandID == commandID && commandID.rawValue != 0 }
    }

    /// The first item of a command ID, nil if there is none.
    public func item(withCommandID commandID: FourCharCode) -> MenuItem? {
        index(ofCommandID: commandID).map { items[$0] }
    }

    /// SetItemMark.
    public func setMark(_ mark: MenuMark, at index: Int) {
        items[index].mark = mark
    }

    /// CheckMenuItem: the check mark, or none.
    public func check(_ checked: Bool, at index: Int) {
        items[index].mark = checked ? .checkmark : .none
    }

    /// EnableMenuItem.
    public func setEnabled(_ enabled: Bool, at index: Int) {
        items[index].isEnabled = enabled
    }

    /// IsMenuItemEnabled: the item's own state.
    public func isEnabled(at index: Int) -> Bool {
        items[index].isEnabled
    }

    /// SetMenuItemKeyEquivalent.
    public func setKeyEquivalent(_ key: UInt8, modifiers: MenuKeyModifiers, at index: Int) {
        items[index].key = key
        items[index].modifiers = modifiers
    }

    // MARK: Finding by key

    /// The first enabled item whose keyboard equivalent is the character
    /// held with these modifiers — the part of MenuKey a menu answers
    /// alone.
    public func index(ofKey key: UInt8, modifiers: MenuKeyModifiers) -> Int? {
        items.firstIndex {
            $0.isEnabled && $0.key == key && $0.modifiers == modifiers && $0.key != 0
        }
    }

    // MARK: Attributes

    /// ChangeMenuAttributes.
    public func changeAttributes(add: MenuAttributes = [], remove: MenuAttributes = []) {
        attributes.subtract(remove)
        attributes.formUnion(add)
    }

    /// The parts an AppendMenu string holds items in: split on
    /// semicolons, as the classic split them.
    private func splitItems(_ data: String) -> [Substring] {
        data.isEmpty ? [] : data.split(separator: ";", omittingEmptySubsequences: false)
    }
}
