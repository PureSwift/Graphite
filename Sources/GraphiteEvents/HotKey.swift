import GraphiteBase

/// The signature and identifier returned to an application for a hot key.
public struct HotKeyID: Hashable, Sendable {
    public var signature: FourCharCode
    public var id: UInt32
    public init(signature: FourCharCode, id: UInt32) {
        self.signature = signature
        self.id = id
    }
}

/// An in-process registry. The host is responsible for requesting global
/// registration from the desktop and reporting key presses and releases.
public final class HotKeyRegistry {
    private struct Combination: Hashable {
        var keyCode: UInt32
        var modifiers: UInt32
    }
    private struct Registration {
        var id: HotKeyID
        var target: EventTarget
    }
    private var registrations: [Combination: Registration] = [:]
    public init() {}

    /// Returns false if this combination is already registered.
    @discardableResult
    public func register(keyCode: UInt32, modifiers: UInt32, id: HotKeyID, target: EventTarget) -> Bool {
        let combination = Combination(keyCode: keyCode, modifiers: modifiers)
        guard registrations[combination] == nil else { return false }
        registrations[combination] = Registration(id: id, target: target)
        return true
    }

    public func unregister(keyCode: UInt32, modifiers: UInt32) {
        registrations.removeValue(forKey: Combination(keyCode: keyCode, modifiers: modifiers))
    }

    /// Delivers to the registered target. The four-character signature and
    /// numeric ID are encoded big-endian in the hot-key direct object.
    @discardableResult
    public func send(keyCode: UInt32, modifiers: UInt32, pressed: Bool, time: Double) -> EventHandlingResult {
        guard let registration = registrations[Combination(keyCode: keyCode, modifiers: modifiers)] else { return .notHandled }
        var writer = BigEndianWriter()
        writer.write(registration.id.signature.rawValue)
        writer.write(registration.id.id)
        var event = CarbonEvent(type: EventType(eventClass: "keyb", kind: pressed ? 5 : 6), time: time)
        event.setParameter("----", type: "hkid", bytes: writer.bytes)
        return registration.target.send(&event)
    }
}
