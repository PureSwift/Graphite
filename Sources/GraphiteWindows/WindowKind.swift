// The kinds of windows and their furniture: the class, which orders and
// activates them; the attributes, which give them close boxes, zoom boxes
// and the rest; the parts FindWindow answers with; the regions
// GetWindowRegion takes; and the features a window definition reports.

import GraphiteBase

/// A window's class: how the Window Manager orders it above the others,
/// when it can be active, and whether it floats above the documents.
/// CreateNewWindow takes one.
public enum WindowClass: UInt32, Hashable, Sendable {

    /// An alert: the user's attention at once.
    case alert = 1
    /// A movable alert: an alert the user can drag, which lets the user go
    /// on working in other applications.
    case movableAlert = 2
    /// A modal window: a dialog the user must finish with first.
    case modal = 3
    /// A movable modal window.
    case movableModal = 4
    /// A floating window: a palette or an inspector above the documents.
    case floating = 5
    /// A document window.
    case document = 6
    /// A utility window: like a floating window, but above every
    /// application's documents.
    case utility = 8
    /// A help window: a help tag, with no frame.
    case help = 10
    /// A sheet: a dialog attached to its parent window.
    case sheet = 11
    /// A toolbar window: a palette below the floating windows.
    case toolbar = 12
    /// A plain window: a one-pixel frame and no title bar.
    case plain = 13
    /// An overlay window: transparent, above every other window, for
    /// drawing over them all.
    case overlay = 14
    /// A sheet alert, like a sheet.
    case sheetAlert = 15
    /// An alternate plain window: a plain window with a black shadow.
    case alternatePlain = 16
    /// A simple window: no frame at all; everything in it is the program's.
    case simple = 18
    /// A drawer: a window that slides out from under its parent.
    case drawer = 20

    /// Whether the class floats: a palette above the documents, ordered
    /// among themselves, which FrontWindow skips.
    public var isFloating: Bool {
        self == .floating || self == .utility || self == .toolbar
    }

    /// The layer the window keeps: the Window Manager holds windows of a
    /// higher layer in front of those of a lower one, however the program
    /// orders them. Overlays are above all, help windows above them but
    /// the palettes, alerts and modals above the palettes, and the
    /// document classes at the bottom.
    public var layer: Int {
        switch self {
        case .overlay: 7
        case .help: 6
        case .alert, .movableAlert, .modal, .movableModal, .sheet, .sheetAlert: 5
        case .floating, .utility: 4
        case .toolbar: 3
        default: 2
        }
    }

    /// kWindowActivationScopeNone, Independent or All: when the window
    /// can be the active one. Floating windows are active independently of
    /// the documents; help windows, overlays and toolbars never are.
    public var activationScope: WindowActivationScope {
        switch self {
        case .floating, .utility: .independent
        case .help, .overlay, .toolbar: .none
        default: .all
        }
    }
}

/// kWindowActivationScope: which windows a window is active among.
public enum WindowActivationScope: Hashable, Sendable {

    /// Never active.
    case none

    /// Active when frontmost among the floating windows, whatever the
    /// documents are doing.
    case independent

    /// Active when frontmost among the documents.
    case all
}

/// A window's class and attributes together: what a window definition is
/// asked about, and what a window's parts answer with. Classic procIDs
/// and variations map to these.
public struct WindowKind: Hashable, Sendable {

    public var windowClass: WindowClass

    public var attributes: WindowAttributes

    public init(windowClass: WindowClass, attributes: WindowAttributes = []) {
        self.windowClass = windowClass
        self.attributes = attributes
    }
}

/// WindowAttributes: a window's furniture and behavior, the bits
/// CreateNewWindow takes. Graphite reads the ones that govern the window's
/// shape and its parts (close box, zoom, collapse, resize, updates,
/// activation, clicks); the ones that describe the host's look (textured,
/// shadowed, live resize) it keeps for the layer that exports Carbon.
public struct WindowAttributes: OptionSet, Hashable, Sendable {

    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// kWindowCloseBoxAttribute.
    public static var closeBox: WindowAttributes { WindowAttributes(rawValue: 1 << 0) }
    /// kWindowHorizontalZoomAttribute.
    public static var horizontalZoom: WindowAttributes { WindowAttributes(rawValue: 1 << 1) }
    /// kWindowVerticalZoomAttribute.
    public static var verticalZoom: WindowAttributes { WindowAttributes(rawValue: 1 << 2) }
    /// kWindowFullZoomAttribute: both zooms.
    public static var fullZoom: WindowAttributes { [.horizontalZoom, .verticalZoom] }
    /// kWindowCollapseBoxAttribute.
    public static var collapseBox: WindowAttributes { WindowAttributes(rawValue: 1 << 3) }
    /// kWindowResizableAttribute.
    public static var resizable: WindowAttributes { WindowAttributes(rawValue: 1 << 4) }
    /// kWindowSideTitlebarAttribute.
    public static var sideTitlebar: WindowAttributes { WindowAttributes(rawValue: 1 << 5) }
    /// kWindowToolbarButtonAttribute.
    public static var toolbarButton: WindowAttributes { WindowAttributes(rawValue: 1 << 6) }
    /// kWindowUnifiedTitleAndToolbarAttribute.
    public static var unifiedTitleAndToolbar: WindowAttributes { WindowAttributes(rawValue: 1 << 7) }
    /// kWindowMetalAttribute.
    public static var textured: WindowAttributes { WindowAttributes(rawValue: 1 << 8) }
    /// kWindowNoTitleBarAttribute.
    public static var noTitleBar: WindowAttributes { WindowAttributes(rawValue: 1 << 9) }
    /// kWindowTexturedSquareCornersAttribute.
    public static var texturedSquareCorners: WindowAttributes { WindowAttributes(rawValue: 1 << 10) }
    /// kWindowMetalNoContentSeparatorAttribute.
    public static var noTexturedContentSeparator: WindowAttributes { WindowAttributes(rawValue: 1 << 11) }
    /// kWindowHasRoundBottomBarCornersAttribute.
    public static var roundBottomBarCorners: WindowAttributes { WindowAttributes(rawValue: 1 << 12) }
    /// kWindowDoesNotCycleAttribute.
    public static var doesNotCycle: WindowAttributes { WindowAttributes(rawValue: 1 << 15) }
    /// kWindowNoUpdatesAttribute: the window keeps no update region, and
    /// InvalWindowRect does nothing.
    public static var noUpdates: WindowAttributes { WindowAttributes(rawValue: 1 << 16) }
    /// kWindowNoActivatesAttribute.
    public static var noActivates: WindowAttributes { WindowAttributes(rawValue: 1 << 17) }
    /// kWindowOpaqueForEventsAttribute: clicks pass through the window.
    public static var opaqueForEvents: WindowAttributes { WindowAttributes(rawValue: 1 << 18) }
    /// kWindowCompositingAttribute.
    public static var compositing: WindowAttributes { WindowAttributes(rawValue: 1 << 19) }
    /// kWindowHighResolutionCapableAttribute.
    public static var highResolutionCapable: WindowAttributes { WindowAttributes(rawValue: 1 << 20) }
    /// kWindowNoShadowAttribute.
    public static var noShadow: WindowAttributes { WindowAttributes(rawValue: 1 << 21) }
    /// kWindowCanBeVisibleWithoutLoginAttribute.
    public static var canBeVisibleWithoutLogin: WindowAttributes { WindowAttributes(rawValue: 1 << 22) }
    /// kWindowAsyncDragAttribute.
    public static var asyncDrag: WindowAttributes { WindowAttributes(rawValue: 1 << 23) }
    /// kWindowStandardHandlerAttribute.
    public static var standardHandler: WindowAttributes { WindowAttributes(rawValue: 1 << 25) }
    /// kWindowHideOnFullScreenAttribute.
    public static var hideOnFullScreen: WindowAttributes { WindowAttributes(rawValue: 1 << 26) }
    /// kWindowInWindowMenuAttribute.
    public static var inWindowMenu: WindowAttributes { WindowAttributes(rawValue: 1 << 27) }
    /// kWindowLiveResizeAttribute.
    public static var liveResize: WindowAttributes { WindowAttributes(rawValue: 1 << 28) }
    /// kWindowIgnoreClicksAttribute: clicks pass through the window.
    public static var ignoreClicks: WindowAttributes { WindowAttributes(rawValue: 1 << 29) }
    /// kWindowNoConstrainAttribute.
    public static var noConstrain: WindowAttributes { WindowAttributes(rawValue: 0x8000_0000) }

    /// kWindowStandardDocumentAttributes: the furniture a document window
    /// usually has.
    public static var standardDocument: WindowAttributes { [.closeBox, .fullZoom, .collapseBox, .resizable] }

    /// kWindowStandardFloatingAttributes.
    public static var standardFloating: WindowAttributes { [.closeBox, .collapseBox] }
}

/// The features a window definition reports of a frame (kWindowMsgGetFeatures):
/// what its parts can do.
public struct WindowFeatures: OptionSet, Hashable, Sendable {

    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// kWindowCanGrow: the frame has a grow box.
    public static var canGrow: WindowFeatures { WindowFeatures(rawValue: 1 << 0) }
    /// kWindowCanZoom.
    public static var canZoom: WindowFeatures { WindowFeatures(rawValue: 1 << 1) }
    /// kWindowCanCollapse.
    public static var canCollapse: WindowFeatures { WindowFeatures(rawValue: 1 << 2) }
    /// kWindowIsModal.
    public static var isModal: WindowFeatures { WindowFeatures(rawValue: 1 << 3) }
    /// kWindowCanGetWindowRegion.
    public static var canGetWindowRegion: WindowFeatures { WindowFeatures(rawValue: 1 << 4) }
    /// kWindowIsAlert.
    public static var isAlert: WindowFeatures { WindowFeatures(rawValue: 1 << 5) }
    /// kWindowHasTitleBar.
    public static var hasTitleBar: WindowFeatures { WindowFeatures(rawValue: 1 << 6) }
    /// kWindowSupportsDragHilite.
    public static var supportsDragHilite: WindowFeatures { WindowFeatures(rawValue: 1 << 7) }
    /// kWindowSupportsModifiedBit.
    public static var supportsModifiedBit: WindowFeatures { WindowFeatures(rawValue: 1 << 8) }
    /// kWindowCanDrawInCurrentPort.
    public static var canDrawInCurrentPort: WindowFeatures { WindowFeatures(rawValue: 1 << 9) }
    /// kWindowCanSetupProxyDragImage.
    public static var canSetupProxyDragImage: WindowFeatures { WindowFeatures(rawValue: 1 << 10) }
    /// kWindowCanMeasureTitle.
    public static var canMeasureTitle: WindowFeatures { WindowFeatures(rawValue: 1 << 11) }
    /// kWindowWantsDisposeAtProcessDeath.
    public static var wantsDisposeAtProcessDeath: WindowFeatures { WindowFeatures(rawValue: 1 << 12) }
    /// kWindowSupportsGetGrowImageRegion.
    public static var supportsGetGrowImageRegion: WindowFeatures { WindowFeatures(rawValue: 1 << 13) }
    /// kWindowIsOpaque.
    public static var isOpaque: WindowFeatures { WindowFeatures(rawValue: 1 << 14) }
}

/// A region of a window (kWindowRegionCode): the structure and the content,
/// which GetWindowBounds also takes, and the parts of the frame.
public enum WindowRegion: UInt16, Hashable, Sendable {

    /// kWindowTitleBarRgn.
    case titleBar = 0
    /// kWindowTitleTextRgn.
    case titleText = 1
    /// kWindowCloseBoxRgn.
    case closeBox = 2
    /// kWindowZoomBoxRgn.
    case zoomBox = 3
    /// kWindowDragRgn: the part of the title bar DragWindow drags by.
    case drag = 5
    /// kWindowGrowRgn.
    case grow = 6
    /// kWindowCollapseBoxRgn.
    case collapseBox = 7
    /// kWindowTitleProxyIconRgn.
    case titleProxyIcon = 8
    /// kWindowStructureRgn: the window and its frame.
    case structure = 32
    /// kWindowContentRgn: where the program draws; empty when the window
    /// is collapsed.
    case content = 33
    /// kWindowUpdateRgn: what needs drawing.
    case update = 34
    /// kWindowOpaqueRgn.
    case opaque = 35
    /// kWindowGlobalPortRgn: the content in global coordinates, not
    /// affected by collapsing.
    case globalPort = 40
    /// kWindowToolbarButtonRgn.
    case toolbarButton = 41
}

/// A window definition's answer to kWindowMsgHitTest: the part of the
/// frame a point of the structure is on.
public enum WindowDefPart: Int16, Hashable, Sendable {

    /// wNoHit.
    case noHit = 0
    /// wInContent.
    case content = 1
    /// wInDrag.
    case drag = 2
    /// wInGrow.
    case grow = 3
    /// wInGoAway.
    case goAway = 4
    /// wInZoomIn: the zoom box, the window in its user state.
    case zoomIn = 5
    /// wInZoomOut: the zoom box, the window in its standard state.
    case zoomOut = 6
    /// wInCollapseBox.
    case collapseBox = 9
    /// wInProxyIcon.
    case proxyIcon = 10
    /// wInToolbarButton.
    case toolbarButton = 11
    /// wInStructure: the frame, out of the parts above.
    case structure = 13
}

/// A part of a window, as FindWindow answers (inDesk, inContent, inDrag,
/// and the rest). inNoWindow is inDesk's other name; FindWindow answers
/// it for a point no window is at.
public enum WindowPart: Int16, Hashable, Sendable {

    /// inDesk.
    case desk = 0
    /// inMenuBar.
    case menuBar = 1
    /// inSysWindow.
    case systemWindow = 2
    /// inContent.
    case content = 3
    /// inDrag.
    case drag = 4
    /// inGrow.
    case grow = 5
    /// inGoAway.
    case goAway = 6
    /// inZoomIn.
    case zoomIn = 7
    /// inZoomOut.
    case zoomOut = 8
    /// inCollapseBox.
    case collapseBox = 11
    /// inProxyIcon.
    case proxyIcon = 12
    /// inToolbarButton.
    case toolbarButton = 13
    /// inStructure.
    case structure = 15

    /// The part a window definition's hit test names.
    init(definition part: WindowDefPart) {
        switch part {
        case .content: self = .content
        case .drag: self = .drag
        case .grow: self = .grow
        case .goAway: self = .goAway
        case .zoomIn: self = .zoomIn
        case .zoomOut: self = .zoomOut
        case .collapseBox: self = .collapseBox
        case .proxyIcon: self = .proxyIcon
        case .toolbarButton: self = .toolbarButton
        case .structure, .noHit: self = .structure
        }
    }
}

/// How RepositionWindow places a window: centered, cascaded or at the
/// alert position, on the main screen or by a parent window.
public enum WindowPositionMethod: UInt32, Hashable, Sendable {

    /// kWindowCenterOnMainScreen.
    case centerOnMainScreen = 1
    /// kWindowCenterOnParentWindow.
    case centerOnParentWindow = 2
    /// kWindowCenterOnParentWindowScreen.
    case centerOnParentWindowScreen = 3
    /// kWindowCascadeOnMainScreen.
    case cascadeOnMainScreen = 4
    /// kWindowCascadeOnParentWindow.
    case cascadeOnParentWindow = 5
    /// kWindowCascadeOnParentWindowScreen.
    case cascadeOnParentWindowScreen = 6
    /// kWindowAlertPositionOnMainScreen.
    case alertPositionOnMainScreen = 7
    /// kWindowAlertPositionOnParentWindow.
    case alertPositionOnParentWindow = 8
    /// kWindowAlertPositionOnParentWindowScreen.
    case alertPositionOnParentWindowScreen = 9
    /// kWindowCascadeStartAtParentWindowScreen.
    case cascadeStartAtParentWindowScreen = 10
}
