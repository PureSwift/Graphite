// A color graphics port: where QuickDraw draws and with what. Its pixels'
// bounds and its port rectangle are in its local coordinates, which
// SetOrigin moves; global coordinates are the device's, where a window's
// port sits.

import GraphiteBase

/// The pen: where it is, its size, mode and pattern, and whether it draws.
public struct PenState: Hashable, Sendable {

    public var location: Point
    public var size: Point
    public var mode: TransferMode
    public var pattern: Pattern
    /// HidePen and ShowPen count: the pen draws at 0 and above.
    public var visibility: Int16

    public init(location: Point = .zero, size: Point = Point(v: 1, h: 1), mode: TransferMode = .patCopy,
                pattern: Pattern = .black, visibility: Int16 = 0) {
        self.location = location
        self.size = size
        self.mode = mode
        self.pattern = pattern
        self.visibility = visibility
    }

    /// PenNormal: a 1×1 black pen in patCopy, wherever it is.
    public mutating func normalize() {
        size = Point(v: 1, h: 1)
        mode = .patCopy
        pattern = .black
    }
}

/// The text a port draws with: TextFont, TextFace, TextSize and TextMode.
public struct TextSettings: Hashable, Sendable {

    /// A font family number: 0 is the system font, 1 the application font.
    public var font: Int16
    /// Style bits: bold 1, italic 2, underline 4, outline 8, shadow 16,
    /// condense 32, extend 64.
    public var face: UInt8
    /// Points; 0 is the font's own size.
    public var size: Int16
    public var mode: TransferMode
    /// SpaceExtra and CharExtra, in Fixed points.
    public var spaceExtra: Fixed
    public var characterExtra: Fixed

    public init(font: Int16 = 0, face: UInt8 = 0, size: Int16 = 0, mode: TransferMode = .srcOr,
                spaceExtra: Fixed = Fixed(rawValue: 0), characterExtra: Fixed = Fixed(rawValue: 0)) {
        self.font = font
        self.face = face
        self.size = size
        self.mode = mode
        self.spaceExtra = spaceExtra
        self.characterExtra = characterExtra
    }
}

public final class Port {

    /// The port's pixels; nil for a port that draws nowhere yet.
    public var pixels: PixelBuffer?

    /// portRect: the part of the plane the port shows, in local coordinates.
    public var portRect: Rect

    /// The pixels' bounds in local coordinates when there are none.
    private var bitsBounds: Rect

    public var pen = PenState()
    public var text = TextSettings()

    public var foreColor: RGBColor = .black
    public var backColor: RGBColor = .white
    /// OpColor: the weight of blend and the pin of addPin and subPin.
    public var opColor = RGBColor(red: 0x7FFF, green: 0x7FFF, blue: 0x7FFF)
    /// HiliteColor.
    public var highlightColor = RGBColor(red: 0x0000, green: 0x0000, blue: 0x0000)

    /// BackPat and FillPat's last patterns.
    public var backPattern: Pattern = .white
    public var fillPattern: Pattern = .black

    /// clipRgn: drawing is kept inside it. A new port's is as wide as can
    /// be.
    public var clipRegion = Region(rect: Rect(top: -32767, left: -32767, bottom: 32767, right: 32767))

    /// visRgn: the part of the port that can be seen: a window's that
    /// others don't cover; a world's, all of it.
    public var visibleRegion: Region

    /// The device the port's pixels are on, for its global coordinates.
    public weak var device: GraphicsDevice?

    /// A port over pixels, showing all of them.
    public init(pixels: PixelBuffer) {
        self.pixels = pixels
        portRect = pixels.bounds
        bitsBounds = pixels.bounds
        visibleRegion = Region(rect: pixels.bounds)
    }

    /// A port with no pixels yet (a window's before it is shown).
    public init(portRect: Rect) {
        self.portRect = portRect
        bitsBounds = portRect
        visibleRegion = Region(rect: portRect)
    }

    /// portBits.bounds or portPixMap's bounds: where the pixels are in local
    /// coordinates.
    public var pixelBounds: Rect {
        get { pixels?.bounds ?? bitsBounds }
        set {
            pixels?.bounds = newValue
            bitsBounds = newValue
        }
    }

    // MARK: Coordinates

    /// SetOrigin: the port rectangle's top left becomes (h, v); its pixels'
    /// bounds and visible region move with it, its clip region doesn't.
    public func setOrigin(h: Int16, v: Int16) {
        let dh = h &- portRect.left, dv = v &- portRect.top
        portRect.offset(dh: dh, dv: dv)
        pixelBounds = pixelBounds.offsetBy(dh: dh, dv: dv)
        visibleRegion = visibleRegion.offsetBy(dh: dh, dv: dv)
    }

    /// LocalToGlobal: the pixels' top left is the device's origin.
    public func localToGlobal(_ point: Point) -> Point {
        point - pixelBounds.topLeft
    }

    /// GlobalToLocal.
    public func globalToLocal(_ point: Point) -> Point {
        point + pixelBounds.topLeft
    }

    // MARK: Drawing's limits

    /// Where drawing lands: the port rectangle within its clip and visible
    /// regions and its pixels.
    public var drawableRegion: Region {
        Region(rect: portRect.intersection(pixelBounds)).intersection(clipRegion).intersection(visibleRegion)
    }

    /// ClipRect.
    public func clip(to rect: Rect) {
        clipRegion = Region(rect: rect)
    }

    // MARK: The pen

    /// MoveTo.
    public func move(to point: Point) { pen.location = point }

    /// Move.
    public func move(dh: Int16, dv: Int16) { pen.location += Point(v: dv, h: dh) }

    /// HidePen and ShowPen.
    public func hidePen() { pen.visibility -= 1 }
    public func showPen() { pen.visibility += 1 }

    public var isPenVisible: Bool { pen.visibility >= 0 }
}
