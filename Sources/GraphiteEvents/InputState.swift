import GraphiteBase
import Synchronization

/// Input state maintained by a host as it receives native input. The key map
/// uses classic virtual key codes: bit n of byte n/8 is key n.
public final class InputState: Sendable {
    private struct State: Sendable {
        var keys = [UInt8](repeating: 0, count: 16)
        var modifiers: UInt32 = 0
        var buttons: UInt32 = 0
        var mouse: Point = .zero
    }
    private let state = Mutex(State())
    public init() {}

    public var keyMap: [UInt8] { state.withLock { $0.keys } }
    public var modifiers: UInt32 {
        get { state.withLock { $0.modifiers } }
        set { state.withLock { $0.modifiers = newValue } }
    }
    public var buttons: UInt32 {
        get { state.withLock { $0.buttons } }
        set { state.withLock { $0.buttons = newValue } }
    }
    public var mouse: Point {
        get { state.withLock { $0.mouse } }
        set { state.withLock { $0.mouse = newValue } }
    }
    public var buttonDown: Bool { buttons & 1 != 0 }

    public func setKey(_ code: UInt8, down: Bool) {
        guard code < 128 else { return }
        state.withLock { state in
            let index = Int(code) / 8
            let mask = UInt8(1) << (code % 8)
            if down { state.keys[index] |= mask } else { state.keys[index] &= ~mask }
        }
    }
    public func isKeyDown(_ code: UInt8) -> Bool {
        guard code < 128 else { return false }
        return state.withLock { $0.keys[Int(code) / 8] & (UInt8(1) << (code % 8)) != 0 }
    }
}
