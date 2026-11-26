import GraphiteBase

/// A Carbon event class and kind.
public struct EventType: Hashable, Sendable {
    public var eventClass: FourCharCode
    public var kind: UInt32
    public init(eventClass: FourCharCode, kind: UInt32) {
        self.eventClass = eventClass
        self.kind = kind
    }
}

/// A typed parameter; its byte representation is agreed by its producer and consumer.
public struct EventParameter: Hashable, Sendable {
    public var type: FourCharCode
    public var bytes: [UInt8]
    public init(type: FourCharCode, bytes: [UInt8]) {
        self.type = type
        self.bytes = bytes
    }
}

/// A Carbon event. Copies have independent parameter tables.
public struct CarbonEvent: Sendable {
    public var type: EventType
    public var time: Double
    public var attributes: UInt32
    public private(set) var parameters: [FourCharCode: EventParameter] = [:]

    public init(type: EventType, time: Double, attributes: UInt32 = 0) {
        self.type = type
        self.time = time
        self.attributes = attributes
    }

    public mutating func setParameter(_ name: FourCharCode, type: FourCharCode, bytes: [UInt8]) {
        parameters[name] = EventParameter(type: type, bytes: bytes)
    }

    public func parameter(_ name: FourCharCode, type: FourCharCode? = nil) -> EventParameter? {
        guard let parameter = parameters[name], type == nil || parameter.type == type else { return nil }
        return parameter
    }

    public mutating func removeParameter(_ name: FourCharCode) {
        parameters.removeValue(forKey: name)
    }
}
