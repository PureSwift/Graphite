// Reading a 'MENU' resource, as GetMenu read one: the menu's ID, the
// placeholders the Menu Manager filled with the menu's size, the resource
// ID of the menu definition procedure, the enabled flags of the menu and
// its first 31 items, the title, and the items — each its text and its
// icon, keyboard equivalent, mark and style, ended by a zero byte. A
// submenu an item has, the mark field keeping the submenu's menu ID with
// $1B for the key, reads as the classic kept it.

import GraphiteBase
import struct Foundation.Data
import protocol Foundation.ContiguousBytes

public extension Menu {

    /// GetMenu: a menu from a 'MENU' resource's bytes. menuInvalidErr for
    /// bytes a menu can't be read from. Bytes past the last item are
    /// ignored, as the classic's GetMenu ignored them.
    convenience init(bytes: some ContiguousBytes) throws(MacError) {
        var reader = BigEndianReader(bytes)
        do {
            let menuID = try reader.read(Int16.self)
            _ = try reader.read(Int16.self) // menuWidth, a placeholder GetMenu filled in.
            _ = try reader.read(Int16.self) // menuHeight.
            _ = try reader.read(Int16.self) // The definition procedure's resource ID; 0 the standard one's.
            _ = try reader.read(Int16.self) // A placeholder.
            let enabledFlags = try reader.read(UInt32.self)
            let title = try reader.readPascalString()
            self.init(menuID: menuID, title: title)
            var number = 0
            while true {
                // An item's text length, 0 the end of the items.
                guard try reader.peek(UInt8.self, at: reader.offset) != 0 else {
                    _ = try reader.read(UInt8.self)
                    break
                }
                number += 1
                var item = MenuItem(text: try reader.readPascalString())
                // The standard definition draws an item whose text is a
                // hyphen as a divider line.
                item.isSeparator = item.text.bytes == [UInt8(ascii: "-")]
                item.icon = try reader.read(UInt8.self)
                item.key = try reader.read(UInt8.self)
                let mark = try reader.read(UInt8.self)
                item.style = MenuItemStyle(rawValue: try reader.read(UInt8.self))
                // The enable flags' bit 0 is the menu's own; item i's is bit
                // i, and past 31 they are enabled, as the Menu Manager made
                // them.
                item.isEnabled = number <= 31 ? enabledFlags >> number & 1 == 1 : true
                if item.key == 0x1B {
                    // The mark field keeps the submenu's menu ID, with $1B
                    // for the key.
                    item.submenuID = Int16(mark)
                    item.mark = .none
                } else {
                    item.mark = MenuMark(rawValue: UInt16(mark))
                }
                append(item)
            }
            isEnabled = enabledFlags & 1 == 1
        } catch {
            throw MacError.menuInvalid
        }
    }
}
