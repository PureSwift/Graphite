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

    /// Builds a structure-coordinate display list, including a simple frame
    /// and title bar around the content. Hosts using system decorations can
    /// continue to use `render(window:controls:dialog:version:)`.
    public func renderFrame(window: Window, controls: [Control] = [], dialog: Dialog? = nil, version: Int = 0) -> DisplayList {
        let structure = window.structureBounds
        let content = window.contentBounds
        let width = CGFloat(structure.width), height = CGFloat(structure.height)
        let offsetX = CGFloat(Int(content.left) - Int(structure.left))
        let offsetY = CGFloat(Int(content.top) - Int(structure.top))
        let edge = ResolvedColor(red: 0.2, green: 0.2, blue: 0.2)
        let titleColor = ResolvedColor(red: 0.87, green: 0.87, blue: 0.87)
        var items: [DisplayList.Item] = []
        func add(_ frame: CGRect, _ content: DisplayList.Content) {
            items.append(.init(frame: frame, identity: items.count, version: version, value: .content(content)))
        }
        add(CGRect(x: 0, y: 0, width: width, height: height), .color(edge))
        if offsetY > 0 {
            add(CGRect(x: 1, y: 1, width: max(0, width - 2), height: max(0, offsetY - 1)), .color(titleColor))
            let run = ResolvedText.Run(string: MacRoman.decode(window.title.bytes), font: ResolvedFont(size: 12), color: edge)
            add(CGRect(x: max(4, offsetX + 4), y: 2, width: max(0, width - 16), height: max(0, offsetY - 3)), .text(ResolvedText(runs: [run], alignment: .center)))
        }
        for var item in render(window: window, controls: controls, dialog: dialog, version: version).items {
            item.frame = item.frame.offsetBy(dx: offsetX, dy: offsetY)
            item.identity = items.count
            items.append(item)
        }
        return DisplayList(items: items)
    }

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
                    if item.kind == .editText {
                        if dialog.keyboardFocus == index + 1 && item.isEnabled {
                            let focus = ResolvedColor(red: 0.2, green: 0.45, blue: 0.8)
                            add(bounds.insetBy(dx: -2, dy: -2), .color(focus))
                        }
                        add(bounds, .color(item.isEnabled ? black : gray))
                        let inner = bounds.insetBy(dx: 1, dy: 1)
                        if inner.width > 0 && inner.height > 0 { add(inner, .color(white)) }
                    }
                    if let value = dialog.drawnText(of: index + 1) { text(value, in: bounds, enabled: item.isEnabled) }
                }
            }
        }
        for control in (dialog.map { $0.controlList.controls } ?? controls).reversed() where control.isVisible {
            let bounds = frame(control.bounds)
            let enabled = control.isEnabled && control.isActive
            let edge = enabled ? black : gray
            let pressed = control.hilitedPart != .none
            switch control.kind {
            case .checkBox, .radioButton:
                let size = min(bounds.height, 14)
                let mark = CGRect(x: bounds.minX, y: bounds.minY + (bounds.height - size) / 2, width: size, height: size)
                if control.kind == .radioButton {
                    add(mark, .roundedRectangle(.init(color: edge, cornerRadius: size / 2)))
                    add(mark.insetBy(dx: 1, dy: 1), .roundedRectangle(.init(color: white, cornerRadius: max(0, size / 2 - 1))))
                    if control.value != 0 { add(mark.insetBy(dx: 4, dy: 4), .roundedRectangle(.init(color: edge, cornerRadius: size / 2))) }
                } else {
                    add(mark, .color(edge))
                    add(mark.insetBy(dx: 1, dy: 1), .color(white))
                    if control.value != 0 { text("X", in: mark, enabled: enabled) }
                }
                text(control.title, in: CGRect(x: mark.maxX + 4, y: bounds.minY, width: max(0, bounds.maxX - mark.maxX - 4), height: bounds.height), enabled: enabled)
            case .scrollBar:
                add(bounds, .color(gray))
                let vertical = bounds.height >= bounds.width
                let span = vertical ? bounds.height : bounds.width
                let thumb = min(span, max(8, vertical ? bounds.width : bounds.height))
                let range = max(0, Double(control.maximum) - Double(control.minimum))
                let fraction = range == 0 ? 0 : max(0, min(1, (Double(control.value) - Double(control.minimum)) / range))
                let offset = (span - thumb) * fraction
                let thumbRect = vertical ? CGRect(x: bounds.minX, y: bounds.minY + offset, width: bounds.width, height: thumb) : CGRect(x: bounds.minX + offset, y: bounds.minY, width: thumb, height: bounds.height)
                add(thumbRect.insetBy(dx: 1, dy: 1), .color(edge))
            default:
                if let dialog, dialog.defaultItem > 0,
                   dialog.control(of: dialog.defaultItem) === control, enabled {
                    add(bounds.insetBy(dx: -3, dy: -3), .roundedRectangle(.init(color: black, cornerRadius: 7)))
                    add(bounds.insetBy(dx: -1, dy: -1), .roundedRectangle(.init(color: white, cornerRadius: 5)))
                }
                add(bounds, .roundedRectangle(.init(color: edge, cornerRadius: 4)))
                let inset = bounds.insetBy(dx: 1, dy: 1)
                if inset.width > 0 && inset.height > 0 { add(inset, .roundedRectangle(.init(color: pressed ? gray : white, cornerRadius: 3))) }
                text(control.title, in: inset, enabled: enabled)
            }
        }
        return DisplayList(items: items)
    }
}
