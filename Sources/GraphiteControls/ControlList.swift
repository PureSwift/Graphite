// A window's controls, as the Control Manager kept them: the list
// GetNewControl added to, DrawControls drew and UpdateControls drew again
// where the window needed it, FindControl searched from the last added
// back, and DisposeControl took one from. Carbon's embedding is here too:
// a root control that holds the rest, as CreateRootControl made it — the
// plain list, without the hierarchy, is the classic's own.

import GraphiteBase

public final class ControlList {

    /// The controls, last added first, as the classic's list held them.
    public private(set) var controls: [Control] = []

    /// The window's root control (CreateRootControl), which holds the rest
    /// as its embedded children; nil where the classic's plain list is
    /// used. A window can't have two: errRootAlreadyExists.
    public private(set) var root: Control?

    public init() {}

    /// How many controls the list holds.
    public var count: Int { controls.count }

    // MARK: Adding and removing

    /// NewControl and GetNewControl's work: a control at the front of the
    /// list, the first FindControl finds.
    public func add(_ control: Control) {
        controls.insert(control, at: 0)
    }

    /// DisposeControl.
    public func remove(_ control: Control) {
        controls.removeAll { $0 === control }
    }

    /// CreateRootControl: a root control that holds the rest as its
    /// embedded children. errRootAlreadyExists where there is one.
    @discardableResult
    public func createRoot() throws(MacError) -> Control {
        guard root == nil else { throw .rootAlreadyExists }
        let root = Control(bounds: .zero, definition: StandardControlDefinition())
        self.root = root
        return root
    }

    // MARK: Finding

    /// FindControl: the frontmost control the point is on, and its part.
    /// A control that is hidden, disabled or of the host's own definition
    /// is passed over, as the classic passed a hidden one; the root
    /// control is never found.
    public func findControl(at point: Point) -> (control: Control, part: ControlPart)? {
        for control in controls where control !== root {
            guard control.isVisible else { continue }
            let part = control.hitTest(point)
            guard part != .none else { continue }
            return (control, part)
        }
        return nil
    }

    /// GetControlByID: the control of the signature and ID.
    public func control(signature: FourCharCode, id: Int32) -> Control? {
        controls.first { $0.identifier?.signature == signature && $0.identifier?.id == id }
    }

    /// GetControlCommandID's find: the control of the command ID.
    public func control(commandID: FourCharCode) -> Control? {
        controls.first { $0.commandID == commandID && commandID.rawValue != 0 }
    }

    // MARK: Drawing

    /// DrawControls and UpdateControls' work, for the host that draws the
    /// controls: the visible ones the rectangle touches, last added first.
    /// A nil rectangle is every visible control, as DrawControls drew.
    public func visibleControls(in rect: Rect? = nil) -> [Control] {
        controls.filter { control in
            control.isVisible && (rect == nil || control.bounds.intersects(rect!))
        }
    }
}
