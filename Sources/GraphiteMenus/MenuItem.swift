// A menu item: its text, and the furniture the classic gave it — a mark
// (the check mark a chosen item wears, the diamond a chosen style wears),
// an icon, a style, a keyboard equivalent with its modifiers, a command ID
// — and a submenu, kept by its menu's ID, as the classic kept it, for the
// menu list to resolve.

import GraphiteBase

/// The style bits of an item's text, as QuickDraw's are: bold 1, italic 2,
/// underline 4, outline 8, shadow 16, condensed 32, extended 64. The
/// classic's '<' metacharacters in an AppendMenu string set the first five.
public struct MenuItemStyle: OptionSet, Hashable, Sendable {

    public var rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Plain, as an item without a style is.
    public static var plain: MenuItemStyle { MenuItemStyle() }
    /// Bold.
    public static var bold: MenuItemStyle { MenuItemStyle(rawValue: 1) }
    /// Italic.
    public static var italic: MenuItemStyle { MenuItemStyle(rawValue: 2) }
    /// Underline.
    public static var underline: MenuItemStyle { MenuItemStyle(rawValue: 4) }
    /// Outline.
    public static var outline: MenuItemStyle { MenuItemStyle(rawValue: 8) }
    /// Shadow.
    public static var shadow: MenuItemStyle { MenuItemStyle(rawValue: 16) }
    /// Condense.
    public static var condense: MenuItemStyle { MenuItemStyle(rawValue: 32) }
    /// Extend.
    public static var extend: MenuItemStyle { MenuItemStyle(rawValue: 64) }
}

/// The mark an item wears at its left: the Menu Manager's glyph codes, or
/// any character. None until one is set. The check mark (CheckMenuItem)
/// and the diamond are the classic's 18 and 19.
public struct MenuMark: Hashable, Sendable {

    /// The glyph or character, as SetItemMark takes it: 0 is none, 18 the
    /// check mark, 19 the diamond, and any other value a character.
    public var rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    /// Any character, as MacRoman holds it; nil for one MacRoman doesn't.
    public init?(_ character: Character) {
        guard let byte = MacRoman.encode(String(character))?.first else { return nil }
        self.init(rawValue: UInt16(byte))
    }

    /// noMark.
    public static var none: MenuMark { MenuMark(rawValue: 0) }
    /// kMenuTabRightGlyph.
    public static var tabRight: MenuMark { MenuMark(rawValue: 0x02) }
    /// kMenuTabLeftGlyph.
    public static var tabLeft: MenuMark { MenuMark(rawValue: 0x03) }
    /// kMenuEnterGlyph.
    public static var enter: MenuMark { MenuMark(rawValue: 0x04) }
    /// kMenuShiftGlyph.
    public static var shift: MenuMark { MenuMark(rawValue: 0x05) }
    /// kMenuControlGlyph.
    public static var control: MenuMark { MenuMark(rawValue: 0x06) }
    /// kMenuOptionGlyph.
    public static var option: MenuMark { MenuMark(rawValue: 0x07) }
    /// kMenuSpaceGlyph.
    public static var space: MenuMark { MenuMark(rawValue: 0x09) }
    /// kMenuDeleteRightGlyph.
    public static var deleteRight: MenuMark { MenuMark(rawValue: 0x0A) }
    /// kMenuReturnGlyph.
    public static var `return`: MenuMark { MenuMark(rawValue: 0x0B) }
    /// kMenuDeleteLeftGlyph.
    public static var deleteLeft: MenuMark { MenuMark(rawValue: 0x17) }
    /// kMenuEscapeGlyph.
    public static var escape: MenuMark { MenuMark(rawValue: 0x1B) }
    /// kMenuClearGlyph.
    public static var clear: MenuMark { MenuMark(rawValue: 0x1C) }
    /// kMenuLeftArrowGlyph.
    public static var leftArrow: MenuMark { MenuMark(rawValue: 0x64) }
    /// kMenuRightArrowGlyph.
    public static var rightArrow: MenuMark { MenuMark(rawValue: 0x65) }
    /// kMenuUpArrowGlyph.
    public static var upArrow: MenuMark { MenuMark(rawValue: 0x68) }
    /// kMenuDownArrowGlyph.
    public static var downArrow: MenuMark { MenuMark(rawValue: 0x6A) }
    /// kMenuCommandGlyph.
    public static var command: MenuMark { MenuMark(rawValue: 0x11) }
    /// kMenuCheckmarkGlyph: the mark CheckMenuItem sets.
    public static var checkmark: MenuMark { MenuMark(rawValue: 0x12) }
    /// kMenuDiamondGlyph.
    public static var diamond: MenuMark { MenuMark(rawValue: 0x13) }
}

/// The modifiers an item's keyboard equivalent is held with
/// (SetMenuItemKeyEquivalentsMask's bits). The Command key is implied:
/// an equivalent works with it held unless noCommand is set.
public struct MenuKeyModifiers: OptionSet, Hashable, Sendable {

    public var rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    /// kMenuNoModifiers.
    public static var none: MenuKeyModifiers { MenuKeyModifiers() }
    /// kMenuShiftModifier.
    public static var shift: MenuKeyModifiers { MenuKeyModifiers(rawValue: 1 << 0) }
    /// kMenuOptionModifier.
    public static var option: MenuKeyModifiers { MenuKeyModifiers(rawValue: 1 << 1) }
    /// kMenuControlModifier.
    public static var control: MenuKeyModifiers { MenuKeyModifiers(rawValue: 1 << 2) }
    /// kMenuNoCommandModifier: without the Command key.
    public static var noCommand: MenuKeyModifiers { MenuKeyModifiers(rawValue: 1 << 3) }
}

/// A menu's attributes, the bits CreateNewMenu takes.
public struct MenuAttributes: OptionSet, Hashable, Sendable {

    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// kMenuAttrExcludesMarkColumn: no room kept for marks.
    public static var excludesMarkColumn: MenuAttributes { MenuAttributes(rawValue: 1 << 0) }
    /// kMenuAttrAutoDisable: the title is disabled when every item is.
    public static var autoDisable: MenuAttributes { MenuAttributes(rawValue: 1 << 2) }
    /// kMenuAttrUsePencilGlyph: the pencil drawn for the Control key.
    public static var usePencilGlyph: MenuAttributes { MenuAttributes(rawValue: 1 << 3) }
    /// kMenuAttrHidden: the title isn't drawn, though the menu is in the
    /// bar — for keyboard equivalents nobody sees.
    public static var hidden: MenuAttributes { MenuAttributes(rawValue: 1 << 4) }
    /// kMenuAttrCondenseSeparators: extra separators at the edges and runs
    /// are hidden.
    public static var condenseSeparators: MenuAttributes { MenuAttributes(rawValue: 1 << 5) }
    /// kMenuAttrDoNotCacheImage.
    public static var doNotCacheImage: MenuAttributes { MenuAttributes(rawValue: 1 << 6) }
    /// kMenuAttrDoNotUseUserCommandKeys.
    public static var doNotUseUserCommandKeys: MenuAttributes { MenuAttributes(rawValue: 1 << 7) }
}

/// One item of a menu, as the classic's menu record kept it: text and
/// furniture, and the enabled state the enable flags' item bits held. A
/// divider is an item whose text is a hyphen, or one marked a separator;
/// the definition draws it a line. A submenu is kept by its menu's ID, as
/// the mark field of the classic's item records kept it, for the menu list
/// to resolve.
public struct MenuItem: Hashable, Sendable {

    /// The item's text, as GetMenuItemText answers.
    public var text: PascalString

    /// SetMenuItemCommandID; 0 is none.
    public var commandID: FourCharCode

    /// SetItemMark; none until one is set.
    public var mark: MenuMark

    /// SetItemIcon: an icon number, 0 for none. The classic looked for the
    /// icon in the resource of the number plus 256.
    public var icon: UInt8

    /// SetItemStyle.
    public var style: MenuItemStyle

    /// SetItemCmd: the keyboard equivalent's character, 0 for none. The
    /// classic's $1B, $1C, $1D and $1E mark an item with a submenu, a script
    /// code, a reduced icon or a small icon instead.
    public var key: UInt8

    /// SetMenuItemKeyEquivalentsMask: what's held with the key.
    public var modifiers: MenuKeyModifiers

    /// The menu ID of the item's submenu, 0 for none: the classic kept a
    /// submenu by its ID, and the menu list resolves it.
    public var submenuID: Int16

    /// kMenuItemAttrSeparator: a divider line. An item whose text is a
    /// hyphen is one, as the classic's were.
    public var isSeparator: Bool

    /// EnableMenuItem's answer for this item.
    public var isEnabled: Bool

    public init(text: PascalString = PascalString(), commandID: FourCharCode = FourCharCode(rawValue: 0),
                mark: MenuMark = .none, icon: UInt8 = 0, style: MenuItemStyle = .plain, key: UInt8 = 0,
                modifiers: MenuKeyModifiers = .none, submenuID: Int16 = 0,
                isSeparator: Bool = false, isEnabled: Bool = true) {
        self.text = text
        self.commandID = commandID
        self.mark = mark
        self.icon = icon
        self.style = style
        self.key = key
        self.modifiers = modifiers
        self.submenuID = submenuID
        self.isSeparator = isSeparator
        self.isEnabled = isEnabled
    }

    /// The item the classic's AppendMenu metacharacters make: `(` disables,
    /// `<` is followed by B, I, U, O and S for the style bits, `!` is
    /// followed by a mark, `^` by an icon, `/` by the keyboard equivalent
    /// and ends the text. What's left, in MacRoman, is the item's text; a
    /// hyphen alone divides.
    ///
    /// An item with a submenu keeps the submenu's menu ID in its mark, as
    /// the classic kept it, with $1B for the key: the item "Size!9" with
    /// the character 27 after the slash has the menu of ID 9 for its
    /// submenu.
    public init(classic data: Substring) {
        self.init()
        var text: [UInt8] = []
        var mark: UInt16 = 0
        var characters = data.makeIterator()
        var held: Character?
        items: while let character = held ?? characters.next() {
            held = nil
            switch character {
            case "(":
                isEnabled = false
            case "<":
                styles: while let next = characters.next() {
                    switch next {
                    case "B": style.insert(.bold)
                    case "I": style.insert(.italic)
                    case "U": style.insert(.underline)
                    case "O": style.insert(.outline)
                    case "S": style.insert(.shadow)
                    default: held = next; continue items
                    }
                }
            case "!":
                if let next = characters.next() { mark = UInt16(Self.byte(of: next)) }
            case "^":
                if let next = characters.next() { icon = Self.byte(of: next) }
            case "/":
                if let next = characters.next() { key = Self.byte(of: next) }
                break items
            default:
                if let byte = MacRoman.encode(String(character))?.first { text.append(byte) }
            }
        }
        self.text = PascalString(bytes: text)
        isSeparator = self.text.bytes == [UInt8(ascii: "-")]
        self.mark = MenuMark(rawValue: mark)
        // The $1B keyboard equivalent stands for a submenu, whose menu ID
        // the mark held.
        if key == 0x1B {
            submenuID = Int16(bitPattern: UInt16(truncatingIfNeeded: mark))
            self.mark = .none
        }
    }

    /// A character as the classic's byte-oriented fields kept it: its
    /// MacRoman byte, 0 for a character MacRoman doesn't have.
    private static func byte(of character: Character) -> UInt8 {
        MacRoman.encode(String(character))?.first ?? 0
    }
}
