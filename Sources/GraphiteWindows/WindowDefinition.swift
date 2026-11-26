// Window definitions, the WDEFs, as Swift sees them: the shape of a
// window's frame — where its content sits in its structure, where its
// title bar and its boxes are, what its parts can do — and the size its
// structure takes when the window is zoomed. The standard window classes
// have theirs built in, the look of Mac OS 8 and 9; the layer that exports
// Carbon implements this over a guest's WDEF.

import GraphiteBase
import GraphiteQuickDraw

/// A window definition procedure: the shape of a window of a kind. The
/// Window Manager asks it for everything the frame decides and nothing the
/// program does.
public protocol WindowDefinition: Sendable {

    /// kWindowMsgGetFeatures: what the frame's parts can do.
    func features(of kind: WindowKind) -> WindowFeatures

    /// kWindowMsgCalculateShape: where the content sits in the structure.
    /// A collapsed window has none.
    func contentBounds(within structure: Rect, of kind: WindowKind, isCollapsed: Bool) -> Rect

    /// Where the structure sits around the content: what the Window Manager
    /// works out for a window placed by its content, as CreateNewWindow
    /// places it.
    func structureBounds(around content: Rect, of kind: WindowKind) -> Rect

    /// kWindowMsgGetRegion: a part of the frame, in the structure's
    /// coordinates. A part the window doesn't have is the empty region.
    func region(_ code: WindowRegion, of structure: Rect, kind: WindowKind, isCollapsed: Bool) -> Region

    /// kWindowMsgHitTest: the part of the window a point of its structure
    /// is on, wNoHit outside it. `isInStandardState` tells the zoom box's
    /// state.
    func hitTest(_ point: Point, in structure: Rect, kind: WindowKind,
                 isCollapsed: Bool, isInStandardState: Bool) -> WindowDefPart

    /// ZoomWindow's standard state: the structure the window takes to be
    /// as large as `screen` allows, centered on it. The zoom attributes say
    /// which of the window's dimensions grow to fill it; `contentSize` is
    /// the window's own, which the others keep.
    func standardBounds(of kind: WindowKind, contentSize: Point, on screen: Rect) -> Rect
}

/// The definition the standard window classes use, the look of Mac OS 8
/// and 9: a title bar with the boxes the attributes give it, a four-pixel
/// frame around a document's content, a shorter title bar and no frame on
/// a palette, and nothing at all on a frameless window.
public struct StandardWindowDefinition: WindowDefinition {

    public init() {}

    // MARK: The frame's shape

    /// The title bar's height, 0 for a class without one.
    private func titleBarHeight(of kind: WindowKind) -> Int16 {
        guard !kind.attributes.contains(.noTitleBar) else { return 0 }
        switch kind.windowClass {
        case .alert, .movableAlert, .modal, .movableModal, .document: return 20
        case .floating, .utility, .toolbar: return 17
        default: return 0
        }
    }

    /// The frame around the content's left, right and bottom edges: a
    /// document's platinum border, a plain window's single pixel, nothing
    /// on a frameless window.
    private func frameThickness(of kind: WindowKind) -> Int16 {
        switch kind.windowClass {
        case .alert, .movableAlert, .modal, .movableModal, .document: return 4
        case .plain, .alternatePlain: return 1
        default: return 0
        }
    }

    private func hasTitleBar(of kind: WindowKind) -> Bool {
        titleBarHeight(of: kind) > 0
    }

    public func features(of kind: WindowKind) -> WindowFeatures {
        let attributes = kind.attributes
        var features: WindowFeatures = [.canGetWindowRegion, .isOpaque]
        if attributes.contains(.resizable) { features.insert(.canGrow) }
        if attributes.contains(.fullZoom) { features.insert(.canZoom) }
        if attributes.contains(.collapseBox) { features.insert(.canCollapse) }
        if hasTitleBar(of: kind) {
            features.formUnion([.hasTitleBar, .supportsModifiedBit, .canMeasureTitle])
        }
        switch kind.windowClass {
        case .modal, .movableModal: features.insert(.isModal)
        case .alert, .movableAlert, .sheetAlert: features.insert(.isAlert)
        default: break
        }
        return features
    }

    public func contentBounds(within structure: Rect, of kind: WindowKind, isCollapsed: Bool) -> Rect {
        guard !isCollapsed else { return .zero }
        let title = titleBarHeight(of: kind), frame = frameThickness(of: kind)
        let top = title > 0 ? title : frame
        return Rect(top: structure.top + top, left: structure.left + frame,
                    bottom: structure.bottom - frame, right: structure.right - frame)
    }

    public func structureBounds(around content: Rect, of kind: WindowKind) -> Rect {
        let title = titleBarHeight(of: kind), frame = frameThickness(of: kind)
        let top = title > 0 ? title : frame
        return Rect(top: content.top - top, left: content.left - frame,
                    bottom: content.bottom + frame, right: content.right + frame)
    }

    // MARK: The frame's parts

    /// A box in the title bar: 11 pixels square, four from a side, set to
    /// the bar's middle.
    private func boxRect(topOf bar: Int16, fromEdge: Int16, kind: WindowKind) -> Rect {
        let top = bar + (titleBarHeight(of: kind) - 11) / 2
        return Rect(top: top, left: fromEdge, bottom: top + 11, right: fromEdge + 11)
    }

    private func closeBoxRect(in structure: Rect, kind: WindowKind) -> Rect? {
        guard kind.attributes.contains(.closeBox) else { return nil }
        return boxRect(topOf: structure.top, fromEdge: structure.left + 4, kind: kind)
    }

    private func zoomBoxRect(in structure: Rect, kind: WindowKind) -> Rect? {
        guard kind.attributes.contains(.fullZoom) else { return nil }
        return boxRect(topOf: structure.top, fromEdge: structure.right - 15, kind: kind)
    }

    private func collapseBoxRect(in structure: Rect, kind: WindowKind) -> Rect? {
        guard kind.attributes.contains(.collapseBox) else { return nil }
        // A zoom box, when there is one, sits at the right edge; the
        // collapse box takes the next place to its left.
        let fromEdge = kind.attributes.contains(.fullZoom) ? structure.right - 30 : structure.right - 15
        return boxRect(topOf: structure.top, fromEdge: fromEdge, kind: kind)
    }

    /// The grow box: the bottom-right corner of the content, where a
    /// document's scroll bars meet.
    private func growRect(in structure: Rect, kind: WindowKind) -> Rect? {
        guard kind.attributes.contains(.resizable) else { return nil }
        let content = contentBounds(within: structure, of: kind, isCollapsed: false)
        guard !content.isEmpty, content.width > 15, content.height > 15 else { return nil }
        return Rect(top: content.bottom - 15, left: content.right - 15, bottom: content.bottom, right: content.right)
    }

    private func titleBarRect(of structure: Rect, kind: WindowKind) -> Rect? {
        let height = titleBarHeight(of: kind)
        guard height > 0 else { return nil }
        return Rect(top: structure.top, left: structure.left, bottom: structure.top + height, right: structure.right)
    }

    public func region(_ code: WindowRegion, of structure: Rect, kind: WindowKind, isCollapsed: Bool) -> Region {
        switch code {
        case .structure:
            return Region(rect: structure)
        case .content:
            return Region(rect: contentBounds(within: structure, of: kind, isCollapsed: isCollapsed))
        case .grow:
            return (isCollapsed ? nil : growRect(in: structure, kind: kind)).map { Region(rect: $0) } ?? Region()
        case .update, .globalPort:
            // The Window Manager's own, which it answers before asking the
            // definition.
            return Region()
        case .titleBar, .titleText, .drag, .closeBox, .zoomBox, .collapseBox, .titleProxyIcon, .toolbarButton, .opaque:
            guard let bar = titleBarRect(of: structure, kind: kind) else { return Region() }
            let close = closeBoxRect(in: structure, kind: kind)
            let zoom = isCollapsed ? nil : zoomBoxRect(in: structure, kind: kind)
            let collapse = collapseBoxRect(in: structure, kind: kind)
            switch code {
            case .titleBar:
                return Region(rect: bar)
            case .titleText:
                let left = (close?.right ?? bar.left) + 4
                let right = [zoom?.left, collapse?.left].compactMap { $0 }.min().map { $0 - 4 } ?? bar.right - 4
                guard left < right else { return Region() }
                return Region(rect: Rect(top: bar.top, left: left, bottom: bar.bottom, right: right))
            case .drag:
                var drag = Region(rect: bar)
                for box in [close, zoom, collapse] {
                    if let box { drag = drag.subtracting(Region(rect: box)) }
                }
                return drag
            case .closeBox:
                return close.map { Region(rect: $0) } ?? Region()
            case .zoomBox:
                return zoom.map { Region(rect: $0) } ?? Region()
            case .collapseBox:
                return collapse.map { Region(rect: $0) } ?? Region()
            default:
                return Region()
            }
        }
    }

    public func hitTest(_ point: Point, in structure: Rect, kind: WindowKind,
                        isCollapsed: Bool, isInStandardState: Bool) -> WindowDefPart {
        guard structure.contains(point) else { return .noHit }
        if hasTitleBar(of: kind), let bar = titleBarRect(of: structure, kind: kind), bar.contains(point) {
            if let box = closeBoxRect(in: structure, kind: kind), Region(rect: box).contains(point) { return .goAway }
            // A collapsed window keeps its close and collapse boxes but
            // shows no zoom box.
            if !isCollapsed, let box = zoomBoxRect(in: structure, kind: kind), Region(rect: box).contains(point) {
                return isInStandardState ? .zoomOut : .zoomIn
            }
            if let box = collapseBoxRect(in: structure, kind: kind), Region(rect: box).contains(point) { return .collapseBox }
            return .drag
        }
        if !isCollapsed, let box = growRect(in: structure, kind: kind), Region(rect: box).contains(point) {
            return .grow
        }
        if contentBounds(within: structure, of: kind, isCollapsed: isCollapsed).contains(point) {
            return .content
        }
        return .structure
    }

    public func standardBounds(of kind: WindowKind, contentSize: Point, on screen: Rect) -> Rect {
        let attributes = kind.attributes
        let width = attributes.contains(.horizontalZoom) ? screen.width : Int(contentSize.h)
        let height = attributes.contains(.verticalZoom) ? screen.height : Int(contentSize.v)
        // Centered on the screen, at its edge where the window fills it.
        let left = screen.left + Int16(clamping: (screen.width - width) / 2)
        let top = screen.top + Int16(clamping: (screen.height - height) / 2)
        return Rect(top: top, left: left,
                    bottom: top + Int16(clamping: height), right: left + Int16(clamping: width))
    }
}
