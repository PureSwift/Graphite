#if GRAPHITE_SDL3
import GraphiteBase
import GraphiteEvents
import SDL3Swift

/// SDL owns the event pump: create this after SDL initialization and call
/// `waitForEvents` on SDL's main thread. Events outside the supported input
/// subset are forwarded to `unhandled`, so window and quit events are not lost.
public final class SDLEventHost: EventLoopHost {
    public enum HostError: Error { case cannotReserveWakeEvent }
    private let wakeType: UInt32
    public let input = InputState()
    public var unhandled: (SDLEvent) -> Void
    /// Convert SDL window-local coordinates to global coordinates. Hosts with
    /// multiple windows must provide their window positions.
    public var globalPosition: (UInt32, Float, Float) -> (Float, Float)

    public init(globalPosition: @escaping (UInt32, Float, Float) -> (Float, Float) = { _, x, y in (x, y) },
                unhandled: @escaping (SDLEvent) -> Void) throws {
        guard let wake = SDL.registerEvents() else { throw HostError.cannotReserveWakeEvent }
        wakeType = wake
        self.globalPosition = globalPosition
        self.unhandled = unhandled
    }

    public var eventTime: Double { Double(SDL.ticks) / 1_000_000_000 }

    public func wakeEventLoop() { SDL.pushUserEvent(type: wakeType) }

    public func waitForEvents(until deadline: Double?, queue: EventQueue) {
        let timeout: Int32
        if let deadline {
            let milliseconds = max(0, (deadline - eventTime) * 1000)
            timeout = milliseconds >= Double(Int32.max) ? Int32.max : Int32(milliseconds.rounded(.up))
        } else { timeout = -1 }
        guard let event = SDL.waitEvent(timeout: timeout) else { return }
        process(event, queue: queue)
    }

    /// Translate one SDL event. Useful when an application owns the SDL pump.
    public func process(_ event: SDLEvent, queue: EventQueue) {
        switch event {
        case .user(let type, _, _) where type == wakeType:
            return
        case .mouseMotion(let window, _, _, let x, let y, _, _):
            postMouse(kind: 5, window: window, x: x, y: y, button: nil, queue: queue)
        case .mouseButtonDown(let window, _, let button, _, let x, let y):
            updateButton(button.rawValue, down: true)
            postMouse(kind: 1, window: window, x: x, y: y, button: button.rawValue, queue: queue)
        case .mouseButtonUp(let window, _, let button, _, let x, let y):
            updateButton(button.rawValue, down: false)
            postMouse(kind: 2, window: window, x: x, y: y, button: button.rawValue, queue: queue)
        case .keyDown(let window, let scan, _, let modifiers, let repeated):
            if !postKey(window: window, scan: scan.rawValue, modifiers: modifiers, kind: repeated ? 2 : 1, queue: queue) { unhandled(event) }
        case .textInput(let window, let text):
            guard let bytes = MacRoman.encode(text), !bytes.isEmpty else { unhandled(event); return }
            var translated = CarbonEvent(type: EventType(eventClass: "text", kind: 1), time: eventTime)
            translated.setParameter("text", type: "TEXT", bytes: bytes)
            var windowID = BigEndianWriter(); windowID.write(window)
            translated.setParameter("swin", type: "magn", bytes: windowID.bytes)
            queue.post(translated)
        case .keyUp(let window, let scan, _, let modifiers, _):
            if !postKey(window: window, scan: scan.rawValue, modifiers: modifiers, kind: 3, queue: queue) { unhandled(event) }
        default:
            unhandled(event)
        }
    }

    private func updateButton(_ button: UInt8, down: Bool) {
        guard button > 0, button <= 32 else { return }
        let carbonButton: UInt8 = button == 2 ? 3 : (button == 3 ? 2 : button)
        let mask = UInt32(1) << (carbonButton - 1)
        if down { input.buttons |= mask } else { input.buttons &= ~mask }
    }

    private func postMouse(kind: UInt32, window: UInt32, x: Float, y: Float, button: UInt8?, queue: EventQueue) {
        let (globalX, globalY) = globalPosition(window, x, y)
        guard globalX.isFinite, globalY.isFinite else { return }
        func coordinate(_ value: Float) -> Int16 {
            Int16(max(Float(Int16.min), min(Float(Int16.max), value.rounded())))
        }
        input.mouse = Point(v: coordinate(globalY), h: coordinate(globalX))
        var event = CarbonEvent(type: EventType(eventClass: "mous", kind: kind), time: eventTime)
        var point = BigEndianWriter()
        point.write(globalX.bitPattern); point.write(globalY.bitPattern)
        event.setParameter("mloc", type: "hipt", bytes: point.bytes)
        var windowID = BigEndianWriter(); windowID.write(window)
        event.setParameter("swin", type: "magn", bytes: windowID.bytes)
        var mods = BigEndianWriter(); mods.write(Self.macModifiers(SDL.modifierState))
        event.setParameter("kmod", type: "magn", bytes: mods.bytes)
        if let button {
            let carbonButton: UInt8 = button == 2 ? 3 : (button == 3 ? 2 : button)
            var value = BigEndianWriter(); value.write(UInt16(carbonButton))
            event.setParameter("mbtn", type: "mbtn", bytes: value.bytes)
        }
        queue.post(event)
    }

    private func postKey(window: UInt32, scan: UInt32, modifiers: KeyModifiers, kind: UInt32, queue: EventQueue) -> Bool {
        guard let code = Self.macKeyCode(scan) else { return false }
        let flags = Self.macModifiers(modifiers)
        input.modifiers = flags
        input.setKey(code, down: kind != 3)
        var event = CarbonEvent(type: EventType(eventClass: "keyb", kind: kind), time: eventTime)
        var key = BigEndianWriter(); key.write(UInt32(code))
        var mods = BigEndianWriter(); mods.write(flags)
        event.setParameter("kcod", type: "magn", bytes: key.bytes)
        let special: [UInt8: UInt8] = [36: 13, 53: 27, 51: 8, 48: 9, 123: 28, 124: 29, 125: 31, 126: 30]
        if let character = special[code] { event.setParameter("kchr", type: "char", bytes: [character]) }
        event.setParameter("kmod", type: "magn", bytes: mods.bytes)
        var windowID = BigEndianWriter(); windowID.write(window)
        event.setParameter("swin", type: "magn", bytes: windowID.bytes)
        queue.post(event)
        return true
    }

    private static func macModifiers(_ flags: KeyModifiers) -> UInt32 {
        var value: UInt32 = 0
        if !flags.intersection(.gui).isEmpty { value |= 0x0100 }
        if !flags.intersection(.shift).isEmpty { value |= 0x0200 }
        if flags.contains(.capsLock) { value |= 0x0400 }
        if !flags.intersection(.alt).isEmpty { value |= 0x0800 }
        if !flags.intersection(.control).isEmpty { value |= 0x1000 }
        return value
    }

    /// USB HID scancodes for the standard US keyboard, mapped to Mac virtual keys.
    private static func macKeyCode(_ scan: UInt32) -> UInt8? {
        let letters: [UInt8] = [0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6]
        if (4...29).contains(scan) { return letters[Int(scan - 4)] }
        let others: [UInt32: UInt8] = [30: 18, 31: 19, 32: 20, 33: 21, 34: 23, 35: 22, 36: 26, 37: 28, 38: 25, 39: 29, 40: 36, 41: 53, 42: 51, 43: 48, 44: 49, 45: 27, 46: 24, 47: 33, 48: 30, 49: 42, 51: 41, 52: 39, 53: 50, 54: 43, 55: 47, 56: 44, 79: 124, 80: 123, 81: 125, 82: 126]
        return others[scan]
    }
}
#endif
