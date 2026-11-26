// Menu definitions, the MDEFs, as Swift sees them: the sizes of a menu
// — how tall the bar is, how tall an item, how wide the columns of marks,
// icons and keys — and where an item sits, so the host can draw them. The
// standard definition is the classic's look. Drawing is the host's; the
// definition answers mSizeMsg's and mChooseMsg's questions.

import GraphiteBase

/// A menu definition procedure: the shape of a menu and its items, as the
/// Menu Manager asked and the host draws. mSizeMsg's width and height are
/// its sizes; mChooseMsg's geometry is where an item is and which a point
/// is on.
public protocol MenuDefinition: Sendable {

    /// How tall the menu bar is.
    var menuBarHeight: Int16 { get }

    /// How tall one item is.
    var itemHeight: Int16 { get }

    /// mSizeMsg's height: a menu of so many items.
    func menuHeight(itemCount: Int) -> Int16

    /// mSizeMsg's width: room for the item texts, measured by `measuring`,
    /// and a column each for the marks, icons and keyboard equivalents that
    /// are there. `attributes` says what the menu does without: one that
    /// excludes the mark column keeps none for it.
    func menuWidth(of items: [MenuItem], attributes: MenuAttributes,
                   measuring: (_ text: PascalString) -> Int16) -> Int16

    /// The rectangle an item occupies in a menu's bounds.
    func itemRect(at index: Int, in bounds: Rect) -> Rect

    /// mChooseMsg: the item a point of the menu is on, nil for none.
    func hitTest(_ point: Point, in bounds: Rect, itemCount: Int) -> Int?
}

/// The standard menu definition, the classic's look: a bar 20 pixels tall,
/// items 16, and a column each for the icon, the mark and the key
/// equivalent that the menu's items use, two pixels of margin around.
public struct StandardMenuDefinition: MenuDefinition {

    /// The height of a mark's, an icon's or a key's column.
    private static let columnWidth: Int16 = 16

    /// The margin around a menu.
    private static let margin: Int16 = 2

    public init() {}

    public var menuBarHeight: Int16 { 20 }

    public var itemHeight: Int16 { 16 }

    public func menuHeight(itemCount: Int) -> Int16 {
        Int16(clamping: itemCount) * itemHeight
    }

    public func menuWidth(of items: [MenuItem], attributes: MenuAttributes,
                         measuring: (_ text: PascalString) -> Int16) -> Int16 {
        var width = Self.margin
        if items.contains(where: { $0.icon != 0 }) { width += Self.columnWidth }
        if !attributes.contains(.excludesMarkColumn), items.contains(where: { $0.mark != .none }) {
            width += Self.columnWidth
        }
        let text = items.map { measuring($0.text) }.max() ?? 0
        width += text
        if items.contains(where: { $0.key != 0 && $0.key != 0x1B }) { width += Self.columnWidth }
        width += Self.margin
        return width
    }

    public func itemRect(at index: Int, in bounds: Rect) -> Rect {
        let top = bounds.top + Int16(clamping: index) * itemHeight
        return Rect(top: top, left: bounds.left, bottom: top + itemHeight, right: bounds.right)
    }

    public func hitTest(_ point: Point, in bounds: Rect, itemCount: Int) -> Int? {
        guard bounds.contains(point) else { return nil }
        let index = (Int(point.v) - Int(bounds.top)) / Int(itemHeight)
        guard index >= 0, index < itemCount else { return nil }
        return index
    }
}
