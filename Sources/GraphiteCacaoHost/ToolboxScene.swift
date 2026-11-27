import Foundation
import CacaoHost
import CacaoRender
import GraphiteBase
import GraphiteWindows
import GraphiteDialogs
import GraphiteCacaoRenderer

/// A CacaoHost scene for a Graphite dialog. The caller attaches the dialog
/// to its WindowManager before creating the scene.
@MainActor
public final class ToolboxScene: HostScene {
    public let dialog: Dialog
    public let window: Window
    public var onItemHit: (Int) -> Void
    public var onDetach: () -> Void
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

    public func handle(_ event: HostEvent, time: Double) {
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
        default: translated = nil
        }
        guard let translated else { return }
        var item = 0
        if StandardDialogFilter().filter(dialog, translated, &item) { onItemHit(item) }
        else if let item = dialog.handle(translated) { onItemHit(item) }
        dirty = true
    }

    public func update(_ frame: HostFrame) -> Bool {
        let changed = dirty
        dirty = false
        if changed { revision &+= 1 }
        return changed
    }

    public func displayList() -> DisplayList { renderer.render(window: window, dialog: dialog, version: revision) }
    public func detach() { onDetach() }
}
