import GraphiteBase
import GraphiteQuickDraw

/// A port over new 1-bit pixels, white.
func bitmapPort(width: Int16, height: Int16) -> Port {
    Port(pixels: PixelBuffer(bounds: Rect(top: 0, left: 0, bottom: height, right: width), format: .indexed(depth: 1)))
}

/// A buffer's pixels as text, a row a line: "#" for black, "." for white,
/// "o" for any other color.
func snapshot(_ pixels: PixelBuffer) -> String {
    var lines: [String] = []
    for v in pixels.bounds.top ..< pixels.bounds.bottom {
        var line = ""
        for h in pixels.bounds.left ..< pixels.bounds.right {
            switch pixels.color(at: Point(v: v, h: h)) {
            case .black: line += "#"
            case .white: line += "."
            default: line += "o"
            }
        }
        lines.append(line)
    }
    return lines.joined(separator: "\n")
}

func snapshot(_ port: Port) -> String {
    port.pixels.map(snapshot) ?? ""
}
