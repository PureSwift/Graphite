// A control: the rectangle it occupies in its window, its value and its
// range, its title and its reference value, its visibility, enabling and
// activity, and the action procedure the classic's TrackControl called as
// the user worked the control. The host draws it and tracks it; the
// definition gives its parts' shapes, and the Control Manager keeps the
// rest.

import GraphiteBase

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

public final class Control {

    /// The kind of control the standard definition functions draw; a
    /// control a host defines of its own keeps nil here.
    public let kind: ControlKind?

    /// The shape of the control's parts. The standard kinds share one.
    public let definition: any ControlDefinition

    /// The control's rectangle, in its owner's local coordinates
    /// (GetControlBounds, SetControlBounds, MoveControl, SizeControl).
    public internal(set) var bounds: Rect

    /// GetControlValue, SetControlValue: the control's setting — a button's
    /// 0, a checkbox's or radio button's 0 or 1, a scroll bar's place in
    /// its range, a pop-up menu's chosen item from 1.
    public var value: Int32 = 0 {
        didSet { value = min(max(value, minimum), max(minimum, maximum)) }
    }

    /// GetControlMinimum, SetControlMinimum.
    public var minimum: Int32 = 0

    /// GetControlMaximum, SetControlMaximum. A scroll bar whose maximum
    /// meets its minimum is inactive, as the classic's definition made it,
    /// and active again when the range opens. A pop-up menu keeps its
    /// menu's resource ID in its minimum and its title's width in its
    /// maximum, so a maximum below a minimum is allowed: the classic's own
    /// fields were the program's to read.
    public var maximum: Int32 = 0

    /// GetControlReference, SetControlReference: whatever the program
    /// keeps with the control. A pop-up menu keeps its menu's resource ID.
    public var reference: Int32 = 0

    /// GetControlTitle, SetControlTitle.
    public var title: PascalString

    /// ShowControl and HideControl.
    public internal(set) var isVisible = true

    /// EnableControl and DisableControl. A disabled control draws dimmed
    /// and is hit nowhere.
    public internal(set) var isEnabled = true

    /// ActivateControl and DeactivateControl: an active control is the
    /// one its window's user can work. An inactive one draws as the
    /// classic's inactive controls did, but is hit as ever.
    public internal(set) var isActive = true

    /// HiliteControl: the part drawn pressed, as TrackControl pressed a
    /// button while the mouse was down in it; none while it isn't.
    public internal(set) var hilitedPart: ControlPart = .none

    /// SetControlCommandID; 0 is none.
    public var commandID: GraphiteBase.FourCharCode = GraphiteBase.FourCharCode(rawValue: 0)

    /// SetControlID: the signature and the ID the Control Manager finds a
    /// control by (GetControlByID).
    public var identifier: (signature: GraphiteBase.FourCharCode, id: Int32)?

    /// SetControlAction, GetControlAction: the procedure the classic's
    /// TrackControl called over and over as the user held the control —
    /// the part and the reference constant its work took. The host calls
    /// it as it tracks.
    public var action: (@Sendable (_ part: ControlPart, _ reference: Int32) -> Void)?

    /// The control's part a point of its owner is on — FindControl's
    /// answer for this control alone — or none.
    public func hitTest(_ point: Point) -> ControlPart {
        guard let kind else { return .none }
        return definition.hitTest(point, bounds: bounds, kind: kind, value: value,
                                  minimum: minimum, maximum: maximum, isEnabled: isEnabled)
    }

    public init(kind: ControlKind, bounds: Rect, title: PascalString = "",
                definition: (any ControlDefinition)? = nil) {
        self.kind = kind
        self.definition = definition ?? StandardControlDefinition()
        self.bounds = bounds
        self.title = title
        // A button's maximum is 1 and a checkbox's or radio button's 1
        // too, as the classic's resources kept them: on.
        self.maximum = kind == .scrollBar || kind == .popUpMenu ? 0 : 1
    }

    /// A control of the host's own definition: no standard kind, whatever
    /// shape the definition gives it.
    public init(bounds: Rect, definition: any ControlDefinition) {
        self.kind = nil
        self.definition = definition
        self.bounds = bounds
        title = PascalString()
        maximum = 0
    }

    // MARK: Value

    /// GetControlValue's kind: what the control keeps.
    public var valueKind: ControlValueKind {
        kind.map { definition.valueKind(of: $0) } ?? .none
    }

    /// SetControlValue, as the classic pinned it: a value below the
    /// minimum or above the maximum stops at its edge. Kept for the
    /// layer that exports Carbon, which sets the property directly.
    public func setValue(_ newValue: Int32) {
        value = min(max(newValue, minimum), max(minimum, maximum))
    }

    /// The value a scroll bar's thumb is dragged to, at a point of the
    /// bar: the place in its range the point names, the thumb centered
    /// under the point as it is dragged. Not for a control without a
    /// thumb.
    public func value(at point: Point) -> Int32? {
        guard kind == .scrollBar, maximum > minimum else { return nil }
        let vertical = bounds.height >= bounds.width
        let travel = (vertical ? bounds.height : bounds.width) - 2 * 16
        guard travel > 0 else { return value }
        let thumbLength = 16
        let offset = vertical ? Int(point.v) - Int(bounds.top) - 16
                             : Int(point.h) - Int(bounds.left) - 16
        let centered = min(max(offset - thumbLength / 2, 0), Int(travel - thumbLength))
        let place = Int32(Double(centered) * Double(maximum - minimum) / Double(travel - thumbLength))
        return min(max(minimum + place, minimum), maximum)
    }

    /// A checkbox's or radio button's on-or-off answer.
    public var isOn: Bool {
        value != 0
    }

    /// Whether the control can be worked: visible, enabled and active.
    public var isLive: Bool {
        isVisible && isEnabled && isActive
    }

    // MARK: Changes

    /// MoveControl: the control's top left moves to (h, v), its size kept.
    public func move(h: Int16, v: Int16) {
        bounds.offset(dh: h &- bounds.left, dv: v &- bounds.top)
    }

    /// SizeControl: the control takes a new size, its top left kept.
    public func size(width: Int16, height: Int16) {
        bounds = Rect(top: bounds.top, left: bounds.left,
                      bottom: bounds.top + height, right: bounds.left + width)
    }

    /// ShowControl.
    public func show() { isVisible = true }

    /// HideControl.
    public func hide() { isVisible = false }

    /// EnableControl.
    public func enable() { isEnabled = true }

    /// DisableControl.
    public func disable() { isEnabled = false }

    /// ActivateControl.
    public func activate() { isActive = true }

    /// DeactivateControl.
    public func deactivate() { isActive = false }

    /// HiliteControl: the part drawn pressed.
    public func hilite(_ part: ControlPart) {
        hilitedPart = part
    }
}
