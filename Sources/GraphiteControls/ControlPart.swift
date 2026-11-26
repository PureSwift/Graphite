// A control's parts, as FindControl answers them and a control definition
// reports them: the whole of a button, a checkbox or a radio button; the
// arrows, the pages and the thumb of a scroll bar; the pop-up menu's menu
// part. The classic's part codes are the Carbon appearance's: inButton 10,
// inCheckBox 11, inUpButton 20, inDownButton 21, inPageUp 22, inPageDown
// 23, inThumb — the indicator — 129.

import GraphiteBase

/// A part of a control, as FindControl and TrackControl answer with and
/// the Control Manager's routines take (ControlPartCode). 0 is no part.
public struct ControlPart: Hashable, Sendable {

    /// The part code: 0 no part, 10 a button, 11 a checkbox or radio
    /// button, 20 and 21 a scroll bar's arrows, 22 and 23 its pages, 129
    /// its thumb, 254 the whole control drawn disabled, 255 inactive.
    public var rawValue: Int16

    public init(rawValue: Int16) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: Int16) {
        self.rawValue = rawValue
    }

    /// kControlNoPart: no part, the whole control's own code too
    /// (kControlEntireControl).
    public static var none: ControlPart { ControlPart(0) }
    /// inButton, kControlButtonPart: the whole of a button.
    public static var button: ControlPart { ControlPart(10) }
    /// inCheckBox, kControlCheckBoxPart: the whole of a checkbox or radio
    /// button.
    public static var checkBox: ControlPart { ControlPart(11) }
    /// inUpButton, kControlUpButtonPart: the up arrow of a vertical scroll
    /// bar, the left arrow of a horizontal one.
    public static var upButton: ControlPart { ControlPart(20) }
    /// inDownButton, kControlDownButtonPart.
    public static var downButton: ControlPart { ControlPart(21) }
    /// inPageUp, kControlPageUpPart: the gray area above the thumb.
    public static var pageUp: ControlPart { ControlPart(22) }
    /// inPageDown, kControlPageDownPart.
    public static var pageDown: ControlPart { ControlPart(23) }
    /// inThumb, kControlIndicatorPart, kAppearancePartIndicator: the
    /// scroll box, or a slider's indicator.
    public static var thumb: ControlPart { ControlPart(129) }
    /// kAppearancePartMetaDisabled: the whole control, drawn disabled.
    public static var disabled: ControlPart { ControlPart(254) }
    /// kAppearancePartMetaInactive: the whole control, drawn inactive.
    public static var inactive: ControlPart { ControlPart(255) }
}

/// The kinds of control the standard definition functions draw, as the
/// classic's control definition IDs named them: a control definition
/// function's resource ID in the upper 12 bits of the ID and a variation
/// code in the lower 4. GetNewControl reads one from a 'CNTL' resource;
/// the layer that exports Carbon turns a procID into this.
public enum ControlKind: Hashable, Sendable {

    /// pushButProc: a button.
    case button
    /// checkBoxProc.
    case checkBox
    /// radioButProc.
    case radioButton
    /// scrollBarProc: vertical or horizontal, as its rectangle is tall or
    /// wide.
    case scrollBar
    /// popupMenuProc: a pop-up menu, holding its menu's resource ID.
    case popUpMenu

    /// The control definition ID: 16 times the definition function's
    /// resource ID, plus the variation code. useWFont (8), the variation
    /// that draws the title in the window's font, isn't Graphite's: the
    /// definition draws with the system font, as the standard ones did.
    public var definitionID: Int16 {
        switch self {
        case .button: return 0
        case .checkBox: return 1
        case .radioButton: return 2
        case .scrollBar: return 16
        case .popUpMenu: return 1008
        }
    }

    /// The kind of the classic's control definition ID, with its variation
    /// bits: the standard kinds read exactly, and a useWFont variation
    /// (the ID plus 8) reads as its kind; anything else is nil, the
    /// definition the host brings.
    public init?(definitionID: Int16) {
        switch definitionID {
        case 0, 8: self = .button
        case 1, 9: self = .checkBox
        case 2, 10: self = .radioButton
        case 16, 24: self = .scrollBar
        case 1008, 1008 + 8: self = .popUpMenu
        default: return nil
        }
    }
}

/// The kinds of value a control keeps, which the routines that read one
/// answer differently by: a button keeps none; a checkbox or radio button
/// an on-or-off one; a scroll bar a range.
public enum ControlValueKind: Hashable, Sendable {

    /// A control with no setting to read.
    case none

    /// On or off, as GetControlValue answers 1 or 0.
    case onOff

    /// A value in a range, as a scroll bar's or a dial's is.
    case range
}
