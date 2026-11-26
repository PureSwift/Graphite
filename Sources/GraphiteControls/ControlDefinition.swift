// Control definitions, the CDEFs, as Swift sees them: the parts a control
// has and where they are, so the host can draw them and FindControl can
// find them. The standard definition function draws the classic's five:
// buttons, checkboxes, radio buttons, scroll bars and pop-up menus — the
// 'CDEF' resources 0, 1 and 63 of the System file, as their variation
// codes chose.

import GraphiteBase

/// A control definition function: the shape of a control of a kind, as the
/// Control Manager asked its CDEFs. Drawing is the host's; the definition
/// answers where the parts are, which one a point is on, and what the
/// control keeps.
public protocol ControlDefinition: Sendable {

    /// What kind of value the control keeps.
    func valueKind(of kind: ControlKind) -> ControlValueKind

    /// Which part a point of the control is on — inButton, inCheckBox, a
    /// scroll bar's arrows, pages or thumb — or none. A disabled control
    /// is hit nowhere: its part is the whole control drawn disabled. The
    /// control's value and range place its thumb.
    func hitTest(_ point: Point, bounds: Rect, kind: ControlKind, value: Int32,
                 minimum: Int32, maximum: Int32, isEnabled: Bool) -> ControlPart

    /// A scroll bar's thumb, or a slider's indicator, in the control's
    /// bounds: where the control's value puts it.
    func thumbRect(bounds: Rect, kind: ControlKind, value: Int32, minimum: Int32, maximum: Int32) -> Rect?

    /// Where a part of the control is, in its bounds; nil for a part the
    /// control doesn't have.
    func rect(of part: ControlPart, bounds: Rect, kind: ControlKind, value: Int32,
              minimum: Int32, maximum: Int32) -> Rect?
}

/// The standard control definitions' shapes, the classic's look: a
/// button's whole rectangle is its part, a checkbox's and a radio button's
/// too; a scroll bar is its arrows (16 pixels square at the ends), its
/// pages between them and its thumb where its value puts it, at least 16
/// pixels long and never over the arrows.
public struct StandardControlDefinition: ControlDefinition {

    /// A scroll bar's arrow boxes.
    private static let arrowLength: Int16 = 16

    /// A scroll bar's thumb at its shortest.
    private static let minimumThumbLength: Int16 = 16

    public init() {}

    public func valueKind(of kind: ControlKind) -> ControlValueKind {
        switch kind {
        case .button: return .none
        case .checkBox, .radioButton: return .onOff
        case .scrollBar, .popUpMenu: return .range
        }
    }

    /// Whether a scroll bar's rectangle makes it vertical: taller than
    /// wide, as the classic's definition decided.
    private func isVertical(_ bounds: Rect) -> Bool {
        bounds.height >= bounds.width
    }

    public func hitTest(_ point: Point, bounds: Rect, kind: ControlKind, value: Int32,
                       minimum: Int32, maximum: Int32, isEnabled: Bool) -> ControlPart {
        guard bounds.contains(point) else { return .none }
        guard isEnabled else { return .disabled }
        switch kind {
        case .button, .checkBox, .radioButton:
            return kind == .button ? .button : .checkBox
        case .popUpMenu:
            return .button
        case .scrollBar:
            if let up = rect(of: .upButton, bounds: bounds, kind: kind, value: value, minimum: minimum, maximum: maximum),
               up.contains(point) {
                return .upButton
            }
            if let down = rect(of: .downButton, bounds: bounds, kind: kind, value: value, minimum: minimum, maximum: maximum),
               down.contains(point) {
                return .downButton
            }
            if let thumb = thumbRect(bounds: bounds, kind: kind, value: value, minimum: minimum, maximum: maximum),
               thumb.contains(point) {
                return .thumb
            }
            // The pages: the half of the bar above the point pages up, the
            // half below pages down.
            let vertical = isVertical(bounds)
            let midV = bounds.top + Int16(bounds.height / 2), midH = bounds.left + Int16(bounds.width / 2)
            return vertical ? (point.v < midV ? .pageUp : .pageDown) : (point.h < midH ? .pageUp : .pageDown)
        }
    }

    public func thumbRect(bounds: Rect, kind: ControlKind, value: Int32, minimum: Int32, maximum: Int32) -> Rect? {
        guard kind == .scrollBar, maximum > minimum else { return nil }
        let span = maximum - minimum
        let fraction = Double(value - minimum) / Double(span)
        let length = Self.arrowLength
        if isVertical(bounds) {
            let travel = bounds.height - Int(length) * 2
            guard travel >= Self.minimumThumbLength else {
                return Rect(top: bounds.top + length, left: bounds.left,
                            bottom: bounds.bottom - length, right: bounds.right)
            }
            // The classic's thumb: a fixed-size scroll box, its length the
            // arrow's, its place by its value in the travel that's left.
            let thumbLength = length
            let top = bounds.top + length + Int16(Double(travel - Int(thumbLength)) * fraction)
            return Rect(top: top, left: bounds.left, bottom: top + thumbLength, right: bounds.right)
        }
        let travel = bounds.width - Int(length) * 2
        guard travel >= Self.minimumThumbLength else {
            return Rect(top: bounds.top, left: bounds.left + length, bottom: bounds.bottom, right: bounds.right - length)
        }
        let thumbLength = length
        let left = bounds.left + length + Int16(Double(travel - Int(thumbLength)) * fraction)
        return Rect(top: bounds.top, left: left, bottom: bounds.bottom, right: left + thumbLength)
    }

    public func rect(of part: ControlPart, bounds: Rect, kind: ControlKind,
                     value: Int32, minimum: Int32, maximum: Int32) -> Rect? {
        guard kind == .scrollBar else {
            // A button, a checkbox or a radio button is all one part.
            switch part {
            case .button, .checkBox: return bounds
            default: return nil
            }
        }
        let vertical = isVertical(bounds)
        switch part {
        case .upButton:
            return vertical ? Rect(top: bounds.top, left: bounds.left,
                                   bottom: bounds.top + Self.arrowLength, right: bounds.right)
                            : Rect(top: bounds.top, left: bounds.left,
                                   bottom: bounds.bottom, right: bounds.left + Self.arrowLength)
        case .downButton:
            return vertical ? Rect(top: bounds.bottom - Self.arrowLength, left: bounds.left,
                                   bottom: bounds.bottom, right: bounds.right)
                            : Rect(top: bounds.top, left: bounds.right - Self.arrowLength,
                                   bottom: bounds.bottom, right: bounds.right)
        case .thumb:
            return thumbRect(bounds: bounds, kind: kind, value: value, minimum: minimum, maximum: maximum)
        case .pageUp, .pageDown:
            guard let thumb = thumbRect(bounds: bounds, kind: kind, value: value, minimum: minimum, maximum: maximum) else {
                return nil
            }
            if vertical {
                let middle = thumb.top + Int16(thumb.height / 2)
                return part == .pageUp
                    ? Rect(top: bounds.top + Self.arrowLength, left: bounds.left, bottom: middle, right: bounds.right)
                    : Rect(top: middle, left: bounds.left, bottom: bounds.bottom - Self.arrowLength, right: bounds.right)
            }
            let middle = thumb.left + Int16(thumb.width / 2)
            return part == .pageUp
                ? Rect(top: bounds.top, left: bounds.left + Self.arrowLength, bottom: bounds.bottom, right: middle)
                : Rect(top: bounds.top, left: middle, bottom: bounds.bottom, right: bounds.right - Self.arrowLength)
        default:
            return nil
        }
    }
}
