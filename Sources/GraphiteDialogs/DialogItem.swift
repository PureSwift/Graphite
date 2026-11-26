// An item of a dialog box or an alert box: the display rectangle that
// places it in the box, the kind of thing it is — a button, a checkbox, a
// radio button, static text, editable text, a control, an icon, a picture,
// a user item the program draws itself, a help item — whether it is
// enabled, and its text or its resource. Items are numbered from 1 in the
// routines that act on them, as the Dialog Manager numbered them, and from
// 0 by FindDialogItem alone.

import GraphiteBase

/// The kind of a dialog item, as the item list's type byte keeps it
/// (DialogItemType): the low seven bits.
public enum DialogItemKind: UInt8, Hashable, Sendable {

    /// A user item: one the program draws and tracks, with the procedure
    /// it gives the item.
    case userItem = 0
    /// A help item, for the Help Manager.
    case helpItem = 1
    /// A button, its title in its text.
    case button = 4
    /// A checkbox, its title in its text.
    case checkBox = 5
    /// A radio button, its title in its text.
    case radioButton = 6
    /// A control defined by a 'CNTL' resource, the resource's ID in the
    /// item.
    case control = 7
    /// Static text, the text in the item.
    case staticText = 8
    /// Editable text, the text in the item.
    case editText = 16
    /// An icon, an 'ICON' or 'cicn' resource's ID in the item.
    case icon = 32
    /// A picture, a 'PICT' resource's ID in the item.
    case picture = 64

    /// kItemDisableBit: set in an item's type byte when it is disabled.
    public static var disableBit: UInt8 { 128 }

    /// The kind and the enabled state an item's type byte keeps.
    public static func from(typeByte: UInt8) -> (kind: DialogItemKind, isEnabled: Bool) {
        (DialogItemKind(rawValue: typeByte & ~disableBit) ?? .userItem, typeByte & disableBit == 0)
    }

    /// The type byte of a kind and an enabled state.
    public static func typeByte(_ kind: DialogItemKind, isEnabled: Bool) -> UInt8 {
        kind.rawValue | (isEnabled ? 0 : disableBit)
    }

    /// Whether the item is drawn by the program rather than the Dialog
    /// Manager: a user item.
    public var isUserDrawn: Bool {
        self == .userItem
    }

    /// Whether the item is one of the Dialog Manager's own controls, which
    /// take a title.
    public var hasTitle: Bool {
        switch self {
        case .button, .checkBox, .radioButton: true
        default: false
        }
    }

    /// Whether the item keeps text: a title, static text, or editable
    /// text's.
    public var hasText: Bool {
        hasTitle || self == .staticText || self == .editText
    }

    /// Whether the item keeps a resource ID.
    public var hasResource: Bool {
        self == .control || self == .icon || self == .picture || self == .helpItem
    }
}

/// The procedure that draws a user item (UserItemProc): the Dialog Manager
/// calls it with the dialog and the item's number as it draws.
public typealias DialogItemDrawProc = @Sendable (_ dialog: Dialog, _ item: Int) -> Void

/// One item of a dialog box. Its rectangle is in the dialog's local
/// coordinates.
public struct DialogItem: Sendable {

    /// The display rectangle.
    public var bounds: Rect

    public var kind: DialogItemKind

    /// The enable flag: an enabled item reports mouse-downs in it to the
    /// program, a disabled one doesn't and draws dimmed.
    public var isEnabled: Bool

    /// The item's text: a control's title, static text, or editable text's
    /// default.
    public var text: PascalString

    /// The resource ID a control, an icon or a picture keeps, 0 for none.
    public var resourceID: Int16

    /// A user item's draw procedure, set with SetDialogItem; nil for the
    /// other kinds.
    public var drawProcedure: DialogItemDrawProc?

    public init(bounds: Rect, kind: DialogItemKind, text: PascalString = "", resourceID: Int16 = 0,
                isEnabled: Bool = true, drawProcedure: DialogItemDrawProc? = nil) {
        self.bounds = bounds
        self.kind = kind
        self.text = text
        self.resourceID = resourceID
        self.isEnabled = isEnabled
        self.drawProcedure = drawProcedure
    }

    /// The item's type byte as the item list keeps it.
    public var typeByte: UInt8 {
        DialogItemKind.typeByte(kind, isEnabled: isEnabled)
    }

    /// FindDialogItem's test: whether the point is in the display
    /// rectangle.
    public func contains(_ point: Point) -> Bool {
        bounds.contains(point)
    }
}
