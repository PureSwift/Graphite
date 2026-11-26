// A window: where it sits on the screen and what its frame is; its title,
// its reference constant and its parent; whether it is shown, collapsed,
// zoomed and active; the buffer its content is drawn in, and the regions
// the Window Manager keeps for it. The host reads these and shows the
// window as it likes; Graphite holds the window, not its pixels on the
// screen.

import GraphiteBase
import GraphiteQuickDraw

public final class Window {

    public let windowClass: WindowClass

    /// The window's attributes, which ChangeWindowAttributes changes.
    public private(set) var attributes: WindowAttributes

    /// The shape of the window's frame. The standard classes share one.
    public let definition: any WindowDefinition

    weak var manager: WindowManager?

    /// SetWindowKind: what the program uses the window for. 2 is a dialog,
    /// 8 (userKind) the rest.
    public var kindCode: Int16 = 8

    /// SetWRefCon: whatever the program keeps with the window.
    public var referenceConstant: UInt = 0

    /// The window this one belongs to: a sheet's or a drawer's parent.
    public weak var parent: Window?

    /// SetWTitle and GetWTitle.
    public var title: PascalString

    /// The structure region's bounds, in global coordinates. A collapsed
    /// window's are its title bar's alone.
    public private(set) var structureBounds: Rect

    /// The structure's bounds while the window is collapsed; nil while it
    /// is not.
    private var uncollapsedStructure: Rect?

    /// Whether the window is shown. ShowWindow and HideWindow change it.
    public internal(set) var isVisible = false

    /// The part of the content that can be seen, in global coordinates:
    /// what no window in front covers and no edge of the desktop hides.
    /// The Window Manager keeps it; a host shows the rest as it likes.
    public internal(set) var visibleRegion = Region()

    /// The update region, in global coordinates: what needs drawing.
    public internal(set) var updateRegion = Region()

    /// What the port's clip and visible regions were before BeginUpdate.
    var savedClipRegion: Region?
    var savedVisibleRegion: Region?

    /// LockPortBits and UnlockPortBits: the buffer stays where it is
    /// either way; programs ask before they touch it.
    var portBitsLocks = 0

    /// The state the window returns to when ZoomWindow zooms it back from
    /// the standard state: its content's bounds. GetWindowUserState;
    /// SetWindowUserState sets another.
    public private(set) var userState: Rect

    /// SetWindowStandardState's answer, for a window the program sized
    /// itself rather than letting the definition.
    var standardStateOverride: Rect?

    /// The window's content: where the program draws, in local coordinates
    /// with (0, 0) at the content's top left. On Mac OS X every window is
    /// buffered; Graphite's are too.
    public let port: Port

    /// The content's pixels, the buffer the port draws in.
    public var pixels: PixelBuffer {
        port.pixels!
    }

    public init(windowClass: WindowClass, attributes: WindowAttributes, contentBounds: Rect,
                title: PascalString = "", definition: (any WindowDefinition)? = nil, manager: WindowManager?) {
        self.windowClass = windowClass
        self.attributes = attributes
        self.definition = definition ?? StandardWindowDefinition()
        self.manager = manager
        self.title = title
        self.userState = contentBounds
        let structure = self.definition.structureBounds(around: contentBounds,
                                                       of: WindowKind(windowClass: windowClass, attributes: attributes))
        structureBounds = structure
        // The main screen's depth, as a window's buffer has on Mac OS X.
        let format = manager?.quickDraw.mainDevice?.pixels.format ?? .argb32
        let local = Rect(top: 0, left: 0, bottom: Int16(contentBounds.height), right: Int16(contentBounds.width))
        let pixels = PixelBuffer(bounds: local, format: format)
        pixels.fill(local, with: pixels.value(for: .white))
        port = Port(pixels: pixels)
        // A window that isn't shown can be drawn in but seen nowhere.
        port.visibleRegion = Region()
        port.device = manager?.quickDraw.device(for: structure)
    }

    public var kind: WindowKind {
        WindowKind(windowClass: windowClass, attributes: attributes)
    }

    /// What the frame's parts can do, as the window definition reports
    /// them.
    public var features: WindowFeatures {
        definition.features(of: kind)
    }

    // MARK: Bounds

    /// The content region's bounds, in global coordinates: empty when the
    /// window is collapsed.
    public var contentBounds: Rect {
        guard uncollapsedStructure == nil else { return .zero }
        return definition.contentBounds(within: structureBounds, of: kind, isCollapsed: false)
    }

    /// The content's bounds as they are when the window is expanded, even
    /// while it is collapsed.
    public var uncollapsedContentBounds: Rect {
        if let expanded = uncollapsedStructure {
            return definition.contentBounds(within: expanded, of: kind, isCollapsed: false)
        }
        return definition.contentBounds(within: structureBounds, of: kind, isCollapsed: false)
    }

    private var isCollapsed: Bool { uncollapsedStructure != nil }

    /// GetWindowBounds: the structure's, the content's, or the port's in
    /// global coordinates (which collapsing doesn't change). paramErr for
    /// any other region.
    public func bounds(of region: WindowRegion) throws(MacError) -> Rect {
        switch region {
        case .structure: return structureBounds
        case .content: return contentBounds
        case .globalPort: return uncollapsedContentBounds
        default: throw .parameter
        }
    }

    /// SetWindowBounds: the window's structure or its content, in global
    /// coordinates; the other follows around it. paramErr for any other
    /// region.
    public func setBounds(_ rect: Rect, region: WindowRegion) throws(MacError) {
        switch region {
        case .structure:
            apply(structure: rect)
        case .content:
            apply(structure: definition.structureBounds(around: rect, of: kind))
        default:
            throw .parameter
        }
    }

    /// MoveWindow: the content's top left moves to (h, v).
    public func move(h: Int16, v: Int16, front: Bool = false) {
        var content = uncollapsedContentBounds
        content.offset(dh: h &- content.left, dv: v &- content.top)
        try? setBounds(content, region: .content)
        if front { manager?.select(self) }
    }

    /// MoveWindowStructure: the structure's top left moves to (h, v). A
    /// collapsed window's is its title bar's; the window it stands for
    /// moves with it.
    public func moveStructure(h: Int16, v: Int16) {
        var structure = uncollapsedStructure ?? structureBounds
        structure.offset(dh: h &- structure.left, dv: v &- structure.top)
        apply(structure: structure)
    }

    /// SizeWindow: the content takes a new size, its top left staying
    /// where it was. The buffer starts over: the content needs drawing
    /// again, whole.
    public func size(width: Int16, height: Int16) {
        var content = uncollapsedContentBounds
        content = Rect(top: content.top, left: content.left, bottom: content.top + height, right: content.left + width)
        try? setBounds(content, region: .content)
    }

    /// ChangeWindowAttributes.
    public func changeAttributes(add: WindowAttributes = [], remove: WindowAttributes = []) {
        attributes.subtract(remove)
        attributes.formUnion(add)
        manager?.recompute()
    }

    // MARK: Regions and parts

    /// The structure region, in global coordinates: the window and its
    /// frame; a collapsed window's title bar alone.
    public var structureRegion: Region {
        Region(rect: structureBounds)
    }

    /// The content region, in global coordinates.
    public var contentRegion: Region {
        Region(rect: contentBounds)
    }

    /// GetWindowRegion: any of the window's regions, in global
    /// coordinates.
    public func region(_ code: WindowRegion) -> Region {
        switch code {
        case .structure: return structureRegion
        case .content: return contentRegion
        case .update: return updateRegion
        case .globalPort: return Region(rect: uncollapsedContentBounds)
        case .opaque: return structureRegion
        case .titleBar, .titleText, .drag, .closeBox, .zoomBox, .collapseBox, .grow, .titleProxyIcon, .toolbarButton:
            return definition.region(code, of: structureBounds, kind: kind, isCollapsed: isCollapsed)
        }
    }

    /// FindWindow's answer for this window alone: the part the point is
    /// on, nil outside the window's structure.
    public func hitTest(_ point: Point) -> WindowPart? {
        let part = definition.hitTest(point, in: structureBounds, kind: kind,
                                       isCollapsed: isCollapsed, isInStandardState: isInStandardState)
        guard part != .noHit else { return nil }
        return WindowPart(definition: part)
    }

    // MARK: Coordinates

    /// LocalToGlobal: the content's top left is where the port's local
    /// coordinates start.
    public func localToGlobal(_ point: Point) -> Point {
        point + uncollapsedContentBounds.topLeft
    }

    /// GlobalToLocal.
    public func globalToLocal(_ point: Point) -> Point {
        point - uncollapsedContentBounds.topLeft
    }

    /// The screen most of the window is on (GetWindowDeviceH).
    public var device: GraphicsDevice? {
        manager?.quickDraw.device(for: structureBounds)
    }

    // MARK: Zooming, collapsing, ordering

    /// IsWindowInStandardState: whether the window is where ZoomWindow
    /// would put it.
    public var isInStandardState: Bool {
        contentBounds == standardState
    }

    /// GetWindowStandardState: the content's bounds in the standard state,
    /// as large as the desktop allows, centered on it — or the bounds the
    /// program set. Without a Window Manager, the window's own.
    public var standardState: Rect {
        if let override = standardStateOverride { return override }
        guard let manager else { return contentBounds }
        let structure = definition.standardBounds(of: kind,
                                                  contentSize: Point(v: Int16(uncollapsedContentBounds.height),
                                                                     h: Int16(uncollapsedContentBounds.width)),
                                                  on: manager.mainDesktopBounds)
        return definition.contentBounds(within: structure, of: kind, isCollapsed: false)
    }

    /// SetWindowUserState: where the window returns to when it zooms back
    /// from the standard state.
    public func setUserState(_ rect: Rect) {
        userState = rect
    }

    /// SetWindowStandardState.
    public func setStandardState(_ rect: Rect) {
        standardStateOverride = rect
    }

    /// ZoomWindow: between the user state and the standard state, saving
    /// the one it leaves. A window that can't zoom does nothing. With
    /// `front`, the window comes to the front and is made active first.
    public func zoom(front: Bool = false) {
        guard !attributes.intersection([.horizontalZoom, .verticalZoom]).isEmpty else { return }
        if front { manager?.select(self) }
        if isInStandardState {
            guard !userState.isEmpty else { return }
            try? setBounds(userState, region: .content)
        } else {
            userState = contentBounds
            try? setBounds(standardState, region: .content)
        }
    }

    /// CollapseWindow: the window to its title bar, or back. The content
    /// keeps its pixels either way. A window without a title bar can't
    /// collapse.
    public func collapse(_ collapse: Bool = true) {
        guard isCollapsed != collapse else { return }
        if collapse {
            let bar = definition.region(.titleBar, of: structureBounds, kind: kind, isCollapsed: false)
            guard !bar.isEmpty else { return }
            uncollapsedStructure = structureBounds
            structureBounds = Rect(top: structureBounds.top, left: structureBounds.left,
                                   bottom: min(structureBounds.top + Int16(bar.bounds.height), structureBounds.bottom),
                                   right: structureBounds.right)
        } else {
            structureBounds = uncollapsedStructure ?? structureBounds
            uncollapsedStructure = nil
        }
        manager?.recompute()
    }

    /// ExpandWindow.
    public func expand() {
        collapse(false)
    }

    /// ShowWindow: the window is seen, in front of its layer, and active
    /// in its scope.
    public func show() {
        manager?.show(self)
    }

    /// HideWindow.
    public func hide() {
        manager?.hide(self)
    }

    /// SelectWindow: to the front, and active. A hidden window is shown.
    public func select() {
        manager?.select(self)
    }

    /// BringToFront.
    public func bringToFront() {
        manager?.bringToFront(self)
    }

    /// SendBehind: behind another window, which doesn't move.
    public func sendBehind(_ window: Window) {
        manager?.sendBehind(self, behind: window)
    }

    /// ActivateWindow.
    public func activate(_ activate: Bool) {
        manager?.activate(self, activate)
    }

    /// IsWindowActive.
    public var isActive: Bool {
        guard let manager else { return false }
        switch windowClass.activationScope {
        case .all: return manager.activeWindow === self
        case .independent: return manager.activeFloatingWindow === self
        case .none: return false
        }
    }

    /// DisposeWindow: the window is gone from the list.
    public func dispose() {
        manager?.dispose(self)
    }

    // MARK: Changes the Window Manager hears of

    /// Moves the window, sizes its buffer to its content if the content
    /// grew or shrank, and tells the Window Manager.
    internal func apply(structure: Rect) {
        let oldSize = Point(v: Int16(uncollapsedContentBounds.height), h: Int16(uncollapsedContentBounds.width))
        if isCollapsed {
            uncollapsedStructure = structure
            structureBounds = titleStrip(of: structure)
        } else {
            structureBounds = structure
        }
        let content = uncollapsedContentBounds
        let size = Point(v: Int16(content.height), h: Int16(content.width))
        if size != oldSize {
            rebuildContent(ofSize: size)
            // The buffer starts over: the content needs drawing, whole.
            if !attributes.contains(.noUpdates) { updateRegion = Region(rect: content) }
        }
        manager?.recompute()
    }

    /// The structure's title bar alone, of the shape a collapsed window
    /// keeps.
    private func titleStrip(of structure: Rect) -> Rect {
        let bar = definition.region(.titleBar, of: structure, kind: kind, isCollapsed: false)
        guard !bar.isEmpty else { return structure }
        return Rect(top: structure.top, left: structure.left,
                    bottom: min(structure.top + Int16(bar.bounds.height), structure.bottom), right: structure.right)
    }

    /// A new buffer for a resized content, white as a new window's is. The
    /// old contents aren't kept: a resized window draws itself again.
    private func rebuildContent(ofSize size: Point) {
        guard let old = port.pixels else { return }
        let local = Rect(top: 0, left: 0, bottom: size.v, right: size.h)
        let pixels = PixelBuffer(bounds: local, format: old.format, colorTable: old.colorTable)
        pixels.reservedEntries = old.reservedEntries
        pixels.fill(local, with: pixels.value(for: .white))
        port.pixels = pixels
        port.pixelBounds = local
        port.portRect = local
    }
}
