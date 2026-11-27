import Foundation
import CacaoHost
import CacaoRender
import GraphiteBase
import GraphiteWindows
import GraphiteDialogs
import GraphiteEvents
import GraphiteCacaoRenderer

/// A CacaoHost scene for a Graphite dialog. The caller attaches the dialog
/// to its WindowManager before creating the scene.
@MainActor
public final class ToolboxScene: HostScene {
    public let dialog: Dialog
    public let window: Window
    public var onItemHit: (Int) -> Void
    public var onDetach: () -> Void
    public var drawsWindowFrame = false
    /// When set, translated input is posted here for the application to dispatch.
    public var eventQueue: EventQueue?
    /// Called after an event is queued so a host can dispatch it promptly.
    public var didPostEvent: (() -> Void)?
    private var dirty = true
    private var revision = 0
    private let renderer = ToolboxRenderer()

    public init?(dialog: Dialog, onItemHit: @escaping (Int) -> Void, onDetach: @escaping () -> Void = {}) {
        guard let window = dialog.window else { return nil }
        self.dialog = dialog
        self.window = window
        self.onItemHit = onItemHit
        self.onDetach = onDetach
    }

    public var isAnimating: Bool { false }
    public var windowState: HostWindowState {
        HostWindowState(title: MacRoman.decode(dialog.title.bytes), acceptsTextInput: dialog.keyboardFocus != nil)
    }

    /// Notify the scene after application code modifies its dialog or pixels.
    public func invalidate() { dirty = true }

    private var frameOffset: CGPoint {
        guard drawsWindowFrame else { return .zero }
        return CGPoint(x: Int(window.contentBounds.left) - Int(window.structureBounds.left),
                       y: Int(window.contentBounds.top) - Int(window.structureBounds.top))
    }

    public func hitTest(at point: CGPoint) -> HostHitTestResult {
        guard drawsWindowFrame else { return .normal }
        return point.y < frameOffset.y ? .draggable : .normal
    }

    public func handle(_ input: HostEvent, time: Double) {
        let event: HostEvent
        if case .pointer(let phase, let button, let position, let isFromTouch) = input, drawsWindowFrame {
            let offset = frameOffset
            event = .pointer(phase, button: button, at: CGPoint(x: position.x - offset.x, y: position.y - offset.y), isFromTouch: isFromTouch)
        } else { event = input }
        if let eventQueue, let translated = HostEventTranslator().translate(event, window: window, time: time) {
            eventQueue.post(translated)
            didPostEvent?()
            return
        }
        let translated: DialogEvent?
        switch event {
        case .pointer(let phase, button: .primary, at: let position, isFromTouch: _):
            guard position.x.isFinite, position.y.isFinite,
                  position.x >= CGFloat(Int16.min), position.x <= CGFloat(Int16.max),
                  position.y >= CGFloat(Int16.min), position.y <= CGFloat(Int16.max) else { return }
            let point = Point(v: Int16(position.y), h: Int16(position.x))
            switch phase {
            case .began: translated = .mouseDown(point)
            case .moved: translated = .mouseMoved(point)
            case .ended: translated = .mouseUp(point)
            case .cancelled: translated = .mouseUp(Point(v: .min, h: .min))
            }
        case .text(let value):
            guard let bytes = MacRoman.encode(value), !bytes.isEmpty, bytes.count <= 255 else { return }
            translated = .key(characters: PascalString(bytes: bytes), modifiers: 0)
        case .key(let key) where key.isDown:
            let byte: UInt8?
            switch key.key {
            case .returnKey: byte = 13
            case .escape: byte = 27
            case .tab: byte = 9
            case .backspace, .delete: byte = 8
            case .left: byte = 28
            case .right: byte = 29
            case .character(let character) where key.modifiers.contains(.command):
                byte = MacRoman.encode(String(character))?.first
            default: byte = nil
            }
            guard let byte else { return }
            var modifiers: Int16 = 0
            if key.modifiers.contains(.command) { modifiers |= 0x0100 }
            if key.modifiers.contains(.shift) { modifiers |= 0x0200 }
            if key.modifiers.contains(.option) { modifiers |= 0x0800 }
            if key.modifiers.contains(.control) { modifiers |= 0x1000 }
            translated = .key(characters: PascalString(bytes: [byte]), modifiers: modifiers)
        case .geometryChanged, .windowStateChanged, .appearanceChanged:
            invalidate()
            return
        default: translated = nil
        }
        guard let translated else { return }
        var item = 0
        if StandardDialogFilter().filter(dialog, translated, &item) { onItemHit(item) }
        else if let item = dialog.handle(translated) { onItemHit(item) }
        dirty = true
    }

    public func update(_ frame: HostFrame) -> Bool {
        if frame.size.width.isFinite, frame.size.height.isFinite,
           frame.size.width >= 1, frame.size.height >= 1,
           frame.size.width <= CGFloat(Int16.max), frame.size.height <= CGFloat(Int16.max) {
            let extraWidth = drawsWindowFrame ? window.structureBounds.width - window.contentBounds.width : 0
            let extraHeight = drawsWindowFrame ? window.structureBounds.height - window.contentBounds.height : 0
            let requestedWidth = max(1, Int(frame.size.width) - extraWidth)
            let requestedHeight = max(1, Int(frame.size.height) - extraHeight)
            let bounds = window.uncollapsedContentBounds
            // Window.size adds the dimensions to the existing Int16 origin.
            // Ignore host sizes that cannot be represented in global coordinates.
            if let width = Int16(exactly: requestedWidth), let height = Int16(exactly: requestedHeight),
               Int16(exactly: Int(bounds.left) + requestedWidth) != nil,
               Int16(exactly: Int(bounds.top) + requestedHeight) != nil,
               bounds.width != requestedWidth || bounds.height != requestedHeight {
                window.size(width: width, height: height)
                dirty = true
            }
        }
        let changed = dirty
        dirty = false
        if changed { revision &+= 1 }
        return changed
    }

    public func displayList() -> DisplayList {
        drawsWindowFrame ? renderer.renderFrame(window: window, dialog: dialog, version: revision)
                         : renderer.render(window: window, dialog: dialog, version: revision)
    }
    public func detach() {
        dialog.hide()
        onDetach()
    }
}
