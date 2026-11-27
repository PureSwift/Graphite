import Foundation
import CacaoRender
import GraphiteBase
import GraphiteQuickDraw
import GraphiteWindows
import GraphiteControls
import GraphiteDialogs

/// Builds a Cacao display list in window-content coordinates for a host to present.
public struct ToolboxRenderer {
    public init() {}

    public func render(window: Window, controls: [Control] = [], dialog: Dialog? = nil, version: Int = 0) -> DisplayList {
        var items: [DisplayList.Item] = []
        func add(_ rect: CGRect, _ content: DisplayList.Content) {
            items.append(.init(frame: rect, identity: items.count, version: version, value: .content(content)))
        }
        func frame(_ rect: Rect) -> CGRect {
            CGRect(x: Int(rect.left), y: Int(rect.top), width: rect.width, height: rect.height)
        }
        let black = ResolvedColor(red: 0, green: 0, blue: 0)
        let white = ResolvedColor(red: 1, green: 1, blue: 1)
        let gray = ResolvedColor(red: 0.8, green: 0.8, blue: 0.8)
        func text(_ string: PascalString, in rect: CGRect, enabled: Bool = true) {
            let run = ResolvedText.Run(string: MacRoman.decode(string.bytes), font: ResolvedFont(size: 12), color: enabled ? black : gray)
            add(rect, .text(ResolvedText(runs: [run])))
        }
        let pixels = window.pixels
        var rgba: [UInt8] = []
        rgba.reserveCapacity(pixels.width * pixels.height * 4)
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let color = pixels.color(at: Point(v: Int16(y), h: Int16(x))) ?? .white
                rgba.append(contentsOf: [color.red8, color.green8, color.blue8, 255])
            }
        }
        if pixels.width > 0 && pixels.height > 0 {
            let source = ImageSource(pixels: .init(data: Data(rgba), bytesPerRow: pixels.width * 4), width: pixels.width, height: pixels.height, scale: 1)
            add(CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height), .image(ImageContent(source: source)))
        }
        if let dialog {
            for (index, item) in dialog.itemList.items.enumerated() where !dialog.hiddenItems.contains(index + 1) {
                if item.kind == .staticText || item.kind == .editText {
                    let bounds = frame(item.bounds)
                    if item.kind == .editText { add(bounds, .color(white)) }
                    if let value = dialog.drawnText(of: index + 1) { text(value, in: bounds, enabled: item.isEnabled) }
                }
            }
        }
        for control in (dialog.map { $0.controlList.controls } ?? controls).reversed() where control.isVisible {
            let bounds = frame(control.bounds)
            add(bounds, .color(control.hilitedPart == .none ? gray : black))
            let inset = bounds.insetBy(dx: 1, dy: 1)
            if inset.width > 0 && inset.height > 0 { add(inset, .color(white)) }
            text(control.title, in: inset, enabled: control.isEnabled && control.isActive)
        }
        return DisplayList(items: items)
    }
}
