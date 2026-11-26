// Graphics devices and graphics worlds. A device is a screen, or an
// offscreen world's own: its global bounds and its pixels. A world is an
// offscreen port with its pixels and device (NewGWorld, NewGWorldFromPtr),
// which programs draw into and copy from.

import GraphiteBase

/// A screen's display mode, as the host reports it.
public struct DisplayMode: Hashable, Sendable {

    public var width: Int
    public var height: Int
    public var depth: Int
    public var refreshRate: Int

    public init(width: Int, height: Int, depth: Int = 32, refreshRate: Int = 60) {
        self.width = width
        self.height = height
        self.depth = depth
        self.refreshRate = refreshRate
    }
}

public final class GraphicsDevice {

    /// gdRect: where the device is in global coordinates.
    public var bounds: Rect

    /// The device's pixels: a screen's frame buffer or a world's buffer.
    public var pixels: PixelBuffer

    /// Whether it is a screen, rather than an offscreen world's.
    public let isScreen: Bool

    /// A screen's modes, the current first.
    public var displayModes: [DisplayMode]

    /// The color table's entries that SetEntries leaves as they are
    /// (ProtectEntry).
    public internal(set) var protectedEntries: Set<Int> = []

    public init(bounds: Rect, pixels: PixelBuffer, isScreen: Bool, displayModes: [DisplayMode] = []) {
        self.bounds = bounds
        self.pixels = pixels
        self.isScreen = isScreen
        self.displayModes = displayModes
    }

    /// A screen with pixels of its own.
    public static func screen(width: Int16, height: Int16, depth: Int = 32) -> GraphicsDevice {
        let bounds = Rect(top: 0, left: 0, bottom: height, right: width)
        let format = PixelFormat(depth: depth) ?? .argb32
        return GraphicsDevice(bounds: bounds, pixels: PixelBuffer(bounds: bounds, format: format), isScreen: true,
                              displayModes: [DisplayMode(width: Int(width), height: Int(height), depth: depth)])
    }

    /// The device's depth.
    public var depth: Int { pixels.format.depth }
}

/// GWorldFlags NewGWorld and UpdateGWorld take and return.
public struct GraphicsWorldFlags: OptionSet, Hashable, Sendable {

    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// pixPurge.
    public static var purgeable: GraphicsWorldFlags { GraphicsWorldFlags(rawValue: 1 << 0) }
    /// noNewDevice: the world draws for the current device.
    public static var noNewDevice: GraphicsWorldFlags { GraphicsWorldFlags(rawValue: 1 << 1) }
    /// useTempMem.
    public static var useTemporaryMemory: GraphicsWorldFlags { GraphicsWorldFlags(rawValue: 1 << 2) }
    /// keepLocal.
    public static var keepLocal: GraphicsWorldFlags { GraphicsWorldFlags(rawValue: 1 << 3) }
    /// pixelsLocked.
    public static var pixelsLocked: GraphicsWorldFlags { GraphicsWorldFlags(rawValue: 1 << 7) }
    /// clipPix: UpdateGWorld keeps the pixels, clipped to the new bounds.
    public static var clipPixels: GraphicsWorldFlags { GraphicsWorldFlags(rawValue: 1 << 0) }
    /// stretchPix: UpdateGWorld scales the pixels to the new bounds.
    public static var stretchPixels: GraphicsWorldFlags { GraphicsWorldFlags(rawValue: 1 << 1) }
}

public final class GraphicsWorld {

    public let port: Port

    public let device: GraphicsDevice

    /// LockPixels and UnlockPixels: the host keeps pixels where they are
    /// either way; programs ask before they touch them.
    public var pixelsLocked = false

    public var flags: GraphicsWorldFlags

    /// NewGWorld: a world of a depth (0 for the device's), its pixels its
    /// own, cleared. `bounds` is in the world's local coordinates.
    public init(bounds: Rect, depth: Int, colorTable: ColorTable? = nil, device: GraphicsDevice? = nil,
                flags: GraphicsWorldFlags = []) throws(MacError) {
        let depth = depth == 0 ? (device?.depth ?? 32) : depth
        guard let format = PixelFormat(depth: depth) else { throw .parameter }
        guard !bounds.isEmpty else { throw .parameter }
        let pixels = PixelBuffer(bounds: bounds, format: format, colorTable: colorTable)
        self.device = GraphicsDevice(bounds: bounds, pixels: pixels, isScreen: false)
        port = Port(pixels: pixels)
        port.device = self.device
        self.flags = flags
    }

    /// NewGWorldFromPtr: a world over pixels that are the program's.
    public init(pixels: PixelBuffer, flags: GraphicsWorldFlags = []) {
        device = GraphicsDevice(bounds: pixels.bounds, pixels: pixels, isScreen: false)
        port = Port(pixels: pixels)
        port.device = device
        self.flags = flags
    }

    public var pixels: PixelBuffer { device.pixels }
}

/// QuickDraw's state: the screens, the current port and device.
public final class QuickDraw {

    /// The screens, the main one first (GetMainDevice, GetDeviceList).
    public var screens: [GraphicsDevice]

    /// GetPort and SetPort, GetGWorld and SetGWorld.
    public var currentPort: Port?

    /// GetGDevice and SetGDevice.
    public var currentDevice: GraphicsDevice?

    /// The random seed QuickDraw's Random advances.
    public var random = QuickDrawRandom()

    /// The cursor, as InitCursor, SetCursor, HideCursor and ShowCursor leave it.
    public var cursor = CursorState()

    public init(screens: [GraphicsDevice]) {
        self.screens = screens
        currentDevice = screens.first
    }

    public var mainDevice: GraphicsDevice? { screens.first }

    /// SetGWorld: a world's port and device, or a port and a device.
    public func setWorld(_ world: GraphicsWorld) {
        currentPort = world.port
        currentDevice = world.device
    }

    /// GetMaxDevice: the screen most of a global rectangle is on.
    public func device(for rect: Rect) -> GraphicsDevice? {
        screens.max { lhs, rhs in
            let a = lhs.bounds.intersection(rect), b = rhs.bounds.intersection(rect)
            return a.width * a.height < b.width * b.height
        }
    }
}
