// The Window Manager: a program's windows, front to back by class and
// selection; the desktop they sit on, which is QuickDraw's screens without
// the menu bar; FindWindow; and the showing, hiding, ordering, activating
// and zooming that keep every window's visible region and update region
// as the classic Window Manager kept them. The host shows the windows as
// it likes; Graphite holds their state.

import GraphiteBase
import GraphiteQuickDraw

/// A window the manager keeps a weak hold of, as part of its list.
private final class WindowBox {

    weak var window: Window?

    init(_ window: Window) {
        self.window = window
    }
}

public final class WindowManager {

    /// The screens the windows sit on, and the current port and device.
    public let quickDraw: QuickDraw

    /// The menu bar's height on the main screen, which no window draws
    /// over and FindWindow keeps for the desk. Zero on a host with none.
    public var menuBarHeight: Int16 = 20

    /// How far apart cascaded windows sit: a title bar's worth, as an
    /// appearance's own cascade was.
    public var cascadeOffset = Point(v: 20, h: 20)

    /// GetCascadeOrigin: where the next window cascaded on the main screen
    /// goes. The first is at the desktop's upper-left corner; each one
    /// after is below and to the right of the last, from the corner again
    /// when they would run off the desktop.
    public var cascadeOrigin: Point

    /// QDFlushPortBuffer reaches this: the part of a window's content
    /// buffer that has changed, in global coordinates. The host copies it
    /// from the buffer to the screen as it likes.
    public var flushObserver: ((Window, Region) -> Void)?

    /// The frontmost window the user works in: FrontWindow, which skips
    /// the palettes, help windows and overlays.
    public var frontWindow: Window? {
        windows.first {
            $0.isVisible && !$0.windowClass.isFloating && $0.windowClass.activationScope != .none
        }
    }

    /// The frontmost palette: the frontmost visible window of the
    /// floating classes.
    public var frontFloatingWindow: Window? {
        windows.first { $0.isVisible && $0.windowClass.isFloating }
    }

    /// The active window among the documents: the one SelectWindow last
    /// brought to the front.
    public internal(set) var activeWindow: Window?

    /// The active palette, active independently of the documents.
    public internal(set) var activeFloatingWindow: Window?

    private var boxes: [WindowBox] = []

    public init(quickDraw: QuickDraw) {
        self.quickDraw = quickDraw
        if let main = quickDraw.mainDevice {
            cascadeOrigin = Point(v: main.bounds.top + menuBarHeight, h: main.bounds.left)
        } else {
            cascadeOrigin = .zero
        }
    }

    /// The program's windows, front to back. The Window Manager holds them
    /// weakly: a window the program lets go of is gone from the list, its
    /// pixels with it.
    public var windows: [Window] {
        boxes.removeAll { $0.window == nil }
        return boxes.compactMap(\.window)
    }

    // MARK: Making windows

    /// CreateNewWindow: a window of a class, with attributes, its content
    /// at `bounds` in global coordinates, its title, and a window
    /// definition — the standard one when none is given. paramErr for
    /// empty bounds.
    @discardableResult
    public func newWindow(windowClass: WindowClass = .document, attributes: WindowAttributes = [],
                          bounds content: Rect, title: PascalString = "",
                          definition: (any WindowDefinition)? = nil) throws(MacError) -> Window {
        guard !content.isEmpty else { throw .parameter }
        let window = Window(windowClass: windowClass, attributes: attributes, contentBounds: content,
                            title: title, definition: definition, manager: self)
        moveToFrontOfLayer(window)
        return window
    }

    /// GetWindowFromPort: the window a content port belongs to.
    public func window(withPort port: Port) -> Window? {
        windows.first { $0.port === port }
    }

    // MARK: Finding

    /// FindWindow: the part of the desktop a point is on, and the window:
    /// the frontmost whose structure holds it, nil over the menu bar (inMenuBar)
    /// or the desk (inDesk). A window with the ignore-clicks or
    /// opaque-for-events attribute lets the click through to what's
    /// behind it.
    public func findWindow(at point: Point) -> (part: WindowPart, window: Window?) {
        if let menuBar = menuBarBounds, menuBar.contains(point) {
            return (.menuBar, nil)
        }
        for window in windows where window.isVisible {
            guard !window.attributes.contains(.ignoreClicks), !window.attributes.contains(.opaqueForEvents) else { continue }
            if let part = window.hitTest(point) {
                return (part, window)
            }
        }
        return (.desk, nil)
    }

    // MARK: The desktop

    /// The menu bar, on the main screen.
    var menuBarBounds: Rect? {
        guard menuBarHeight > 0, let main = quickDraw.mainDevice else { return nil }
        return Rect(top: main.bounds.top, left: main.bounds.left,
                    bottom: main.bounds.top + menuBarHeight, right: main.bounds.right)
    }

    /// GetGrayRgn's rectangle on the main screen: the screen below the
    /// menu bar, where a window zooms to.
    var mainDesktopBounds: Rect {
        guard let main = quickDraw.mainDevice else { return .zero }
        return Rect(top: main.bounds.top + menuBarHeight, left: main.bounds.left,
                    bottom: main.bounds.bottom, right: main.bounds.right)
    }

    /// The screen most of a window is on, below that screen's menu bar if
    /// it has one.
    private func desktopBounds(of window: Window) -> Rect {
        guard let device = quickDraw.device(for: window.structureBounds) else { return mainDesktopBounds }
        let bounds = device.bounds
        let top = bounds.top + (device === quickDraw.mainDevice ? menuBarHeight : 0)
        return Rect(top: top, left: bounds.left, bottom: bounds.bottom, right: bounds.right)
    }

    /// The desktop: every screen, without the menu bar. No window is
    /// visible outside it.
    public var desktopRegion: Region {
        var region = Region()
        for screen in quickDraw.screens {
            region = region.union(Region(rect: screen.bounds))
        }
        if let menuBar = menuBarBounds {
            region = region.subtracting(Region(rect: menuBar))
        }
        return region
    }

    // MARK: Positioning

    /// RepositionWindow: centers the window, cascades it, or puts it at
    /// the alert position, on the main screen or by a parent window. The
    /// window keeps its size. paramErr when a parent method has none.
    public func reposition(_ window: Window, method: WindowPositionMethod,
                           relativeTo parent: Window? = nil) throws(MacError) {
        let structure = window.structureBounds
        let width = Int(structure.width), height = Int(structure.height)
        var topLeft: Point
        switch method {
        case .centerOnMainScreen:
            topLeft = centered(width: width, height: height, on: mainDesktopBounds)
        case .centerOnParentWindow, .centerOnParentWindowScreen:
            guard let parent else { throw .parameter }
            let target = method == .centerOnParentWindow ? parent.structureBounds : desktopBounds(of: parent)
            topLeft = centered(width: width, height: height, on: target)
        case .cascadeOnMainScreen:
            topLeft = cascadeOrigin
            advanceCascade(for: Point(v: Int16(height), h: Int16(width)), on: mainDesktopBounds)
        case .cascadeOnParentWindow, .cascadeOnParentWindowScreen, .cascadeStartAtParentWindowScreen:
            guard let parent else { throw .parameter }
            let screen = desktopBounds(of: parent)
            let base = method == .cascadeOnParentWindowScreen ? screen.topLeft : parent.structureBounds.topLeft
            topLeft = base + cascadeOffset
        case .alertPositionOnMainScreen, .alertPositionOnParentWindow, .alertPositionOnParentWindowScreen:
            let target: Rect
            switch method {
            case .alertPositionOnMainScreen: target = mainDesktopBounds
            case .alertPositionOnParentWindow:
                guard let parent else { throw .parameter }
                target = parent.structureBounds
            default:
                guard let parent else { throw .parameter }
                target = desktopBounds(of: parent)
            }
            // The alert position: centered across, three eighths of the way
            // down.
            topLeft = Point(v: target.top + Int16(3 * target.height / 8 - height / 2),
                            h: target.left + Int16((target.width - width) / 2))
        }
        window.apply(structure: Rect(top: topLeft.v, left: topLeft.h,
                                     bottom: topLeft.v + Int16(height), right: topLeft.h + Int16(width)))
    }

    /// A size's top left, centered on a rectangle.
    private func centered(width: Int, height: Int, on target: Rect) -> Point {
        Point(v: target.top + Int16((target.height - height) / 2),
              h: target.left + Int16((target.width - width) / 2))
    }

    /// The next cascade's place, past this one, from the corner again when
    /// the next window wouldn't fit.
    private func advanceCascade(for size: Point, on screen: Rect) {
        let next = cascadeOrigin + cascadeOffset
        let off = next.h + size.h >= screen.right || next.v + size.v >= screen.bottom
        cascadeOrigin = off ? screen.topLeft : next
    }

    // MARK: Showing, ordering, activating

    internal func show(_ window: Window) {
        guard !window.isVisible else { return }
        window.isVisible = true
        moveToFrontOfLayer(window)
        activate(window)
        recompute()
    }

    internal func hide(_ window: Window) {
        guard window.isVisible else { return }
        window.isVisible = false
        if activeWindow === window { activeWindow = nextActive(ofScope: .all) }
        if activeFloatingWindow === window { activeFloatingWindow = nextActive(ofScope: .independent) }
        recompute()
    }

    internal func select(_ window: Window) {
        guard window.isVisible else {
            show(window)
            return
        }
        bringToFront(window)
    }

    internal func bringToFront(_ window: Window) {
        moveToFrontOfLayer(window)
        activate(window)
        recompute()
    }

    internal func sendBehind(_ window: Window, behind other: Window) {
        guard window !== other else { return }
        boxes.removeAll { $0.window === window }
        let index = boxes.firstIndex { $0.window === other } ?? boxes.endIndex
        boxes.insert(WindowBox(window), at: index + 1)
        recompute()
    }

    /// ActivateWindow. Making a window active makes no other one not
    /// active: the documents and the palettes are active separately.
    internal func activate(_ window: Window, _ active: Bool) {
        if active {
            guard window.isVisible else { return }
            activate(window)
        } else {
            if activeWindow === window { activeWindow = nil }
            if activeFloatingWindow === window { activeFloatingWindow = nil }
        }
    }

    private func activate(_ window: Window) {
        guard window.isVisible, !window.attributes.contains(.noActivates) else { return }
        switch window.windowClass.activationScope {
        case .all: activeWindow = window
        case .independent: activeFloatingWindow = window
        case .none: break
        }
    }

    /// The window to make active when the active one goes: the frontmost
    /// of the scope that can be.
    private func nextActive(ofScope scope: WindowActivationScope) -> Window? {
        windows.first {
            $0.isVisible && $0.windowClass.activationScope == scope && !$0.attributes.contains(.noActivates)
        }
    }

    internal func dispose(_ window: Window) {
        boxes.removeAll { $0.window === window }
        window.isVisible = false
        if activeWindow === window { activeWindow = nextActive(ofScope: .all) }
        if activeFloatingWindow === window { activeFloatingWindow = nextActive(ofScope: .independent) }
        recompute()
    }

    /// The window's place in the list: in front of the windows of its
    /// layer and below, behind those above it. A window brought forward
    /// goes in front of the others of its layer.
    private func moveToFrontOfLayer(_ window: Window) {
        boxes.removeAll { $0.window == nil }
        boxes.removeAll { $0.window === window }
        let layer = window.windowClass.layer
        let index = boxes.firstIndex { ($0.window?.windowClass.layer ?? 0) <= layer } ?? boxes.endIndex
        boxes.insert(WindowBox(window), at: index)
    }

    // MARK: What can be seen and what needs drawing

    /// Works out every visible window's visible region — its content on
    /// the desktop, less what the windows in front of it cover — and adds
    /// what each window has never been able to see, and so must draw, to
    /// its update region. The part a window covers again stays drawn: the
    /// buffer keeps it.
    internal func recompute() {
        boxes.removeAll { $0.window == nil }
        let desktop = desktopRegion
        var covering = Region()
        for window in boxes.compactMap(\.window) {
            guard window.isVisible else {
                window.visibleRegion = Region()
                window.port.visibleRegion = Region()
                continue
            }
            let visible = window.contentRegion.intersection(desktop).subtracting(covering)
            if !window.attributes.contains(.noUpdates) {
                window.updateRegion = window.updateRegion.union(visible.subtracting(window.visibleRegion))
            }
            window.visibleRegion = visible
            let origin = window.contentBounds.topLeft
            window.port.visibleRegion = visible.offsetBy(dh: -origin.h, dv: -origin.v)
            window.port.device = quickDraw.device(for: window.structureBounds)
            covering = covering.union(window.structureRegion)
        }
    }
}
