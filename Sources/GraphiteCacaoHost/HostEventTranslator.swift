import Foundation
import CacaoHost
import GraphiteBase
import GraphiteEvents
import GraphiteWindows

/// Converts Cacao input to the shared Carbon event representation.
public struct HostEventTranslator {
    public init() {}

    public func translate(_ event: HostEvent, window: Window, time: Double) -> CarbonEvent? {
        switch event {
        case .pointer(let phase, button: .primary, at: let position, isFromTouch: _):
            if phase == .cancelled {
                return CarbonEvent(type: EventType(eventClass: "gdlg", kind: 1), time: time)
            }
            let origin = window.contentBounds
            let x = Double(position.x) + Double(origin.left)
            let y = Double(position.y) + Double(origin.top)
            guard x.isFinite, y.isFinite, x >= Double(Int16.min), x <= Double(Int16.max),
                  y >= Double(Int16.min), y <= Double(Int16.max) else { return nil }
            let kind: UInt32
            switch phase {
            case .began: kind = 1
            case .moved: kind = 5
            case .ended: kind = 2
            case .cancelled: return nil
            }
            var result = CarbonEvent(type: EventType(eventClass: "mous", kind: kind), time: time)
            var data = BigEndianWriter()
            data.write(Float(x).bitPattern); data.write(Float(y).bitPattern)
            result.setParameter("mloc", type: "hipt", bytes: data.bytes)
            return result
        case .text(let value):
            guard let bytes = MacRoman.encode(value), !bytes.isEmpty, bytes.count <= 255 else { return nil }
            var result = CarbonEvent(type: EventType(eventClass: "text", kind: 1), time: time)
            result.setParameter("text", type: "TEXT", bytes: bytes)
            return result
        case .key(let key) where key.isDown:
            let byte: UInt8?
            switch key.key {
            case .returnKey: byte = 13
            case .escape: byte = 27
            case .tab: byte = 9
            case .backspace, .delete: byte = 8
            case .left: byte = 28
            case .right: byte = 29
            case .character(let value) where key.modifiers.contains(.command): byte = MacRoman.encode(String(value))?.first
            default: byte = nil
            }
            guard let byte else { return nil }
            var flags: UInt32 = 0
            if key.modifiers.contains(.command) { flags |= 0x0100 }
            if key.modifiers.contains(.shift) { flags |= 0x0200 }
            if key.modifiers.contains(.option) { flags |= 0x0800 }
            if key.modifiers.contains(.control) { flags |= 0x1000 }
            var result = CarbonEvent(type: EventType(eventClass: "keyb", kind: key.isRepeat ? 2 : 1), time: time)
            result.setParameter("kchr", type: "char", bytes: [byte])
            var modifiers = BigEndianWriter(); modifiers.write(flags)
            result.setParameter("kmod", type: "magn", bytes: modifiers.bytes)
            return result
        default: return nil
        }
    }
}
