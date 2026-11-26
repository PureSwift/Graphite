// Apple events: a descriptor of typeAppleEvent whose attributes say its
// class, ID, target and return and transaction IDs, and whose items are its
// parameters.

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import Synchronization
import GraphiteBase

public struct AppleEvent: Hashable, Sendable {

    public enum Attribute {
        public static var eventClass: GraphiteBase.FourCharCode { "evcl" }
        public static var eventID: GraphiteBase.FourCharCode { "evid" }
        public static var address: GraphiteBase.FourCharCode { "addr" }
        public static var returnID: GraphiteBase.FourCharCode { "rtid" }
        public static var transactionID: GraphiteBase.FourCharCode { "tran" }
        public static var source: GraphiteBase.FourCharCode { "esrc" }
    }

    public enum Parameter {
        /// keyDirectObject.
        public static var directObject: GraphiteBase.FourCharCode { "----" }
        /// keyErrorNumber, in a reply.
        public static var errorNumber: GraphiteBase.FourCharCode { "errn" }
        /// keyErrorString, in a reply.
        public static var errorString: GraphiteBase.FourCharCode { "errs" }
    }

    /// The required events' class and IDs.
    public enum Core {
        /// kCoreEventClass.
        public static var eventClass: GraphiteBase.FourCharCode { "aevt" }
        public static var openApplication: GraphiteBase.FourCharCode { "oapp" }
        public static var reopenApplication: GraphiteBase.FourCharCode { "rapp" }
        public static var openDocuments: GraphiteBase.FourCharCode { "odoc" }
        public static var printDocuments: GraphiteBase.FourCharCode { "pdoc" }
        public static var quitApplication: GraphiteBase.FourCharCode { "quit" }
        /// kAEAnswer: a reply's ID.
        public static var answer: GraphiteBase.FourCharCode { "ansr" }
    }

    /// kAutoGenerateReturnID.
    public static var autoGenerateReturnID: Int16 { -1 }

    private static let nextReturnID = Atomic<Int16>(1)

    public var descriptor: Descriptor

    /// An event's descriptor: errAENotAppleEvent for another.
    public init(_ descriptor: Descriptor) throws(MacError) {
        guard descriptor.isAppleEvent else { throw .notAppleEvent }
        self.descriptor = descriptor
    }

    /// AECreateAppleEvent: an event of a class and ID for a target, with no
    /// parameters. A return ID of kAutoGenerateReturnID gets one of its own.
    public init(eventClass: GraphiteBase.FourCharCode, eventID: GraphiteBase.FourCharCode, target: Descriptor? = nil,
                returnID: Int16 = autoGenerateReturnID, transactionID: Int32 = 0) {
        var descriptor = Descriptor(type: DescriptorType.appleEvent, isKeyed: true)
        var id = returnID
        if id == Self.autoGenerateReturnID {
            id = Self.nextReturnID.wrappingAdd(1, ordering: .relaxed).oldValue
            if id <= 0 { id = 1 }
        }
        descriptor.setAttribute(Attribute.eventClass, Descriptor(code: eventClass))
        descriptor.setAttribute(Attribute.eventID, Descriptor(code: eventID))
        if let target, !target.isNull { descriptor.setAttribute(Attribute.address, target) }
        descriptor.setAttribute(Attribute.returnID, Descriptor(id))
        descriptor.setAttribute(Attribute.transactionID, Descriptor(transactionID))
        self.descriptor = descriptor
    }

    public var eventClass: GraphiteBase.FourCharCode { descriptor.attribute(Attribute.eventClass)?.code ?? GraphiteBase.FourCharCode(0) }

    public var eventID: GraphiteBase.FourCharCode { descriptor.attribute(Attribute.eventID)?.code ?? GraphiteBase.FourCharCode(0) }

    public var address: Descriptor? { descriptor.attribute(Attribute.address) }

    public subscript(parameter keyword: GraphiteBase.FourCharCode) -> Descriptor? {
        get { descriptor[keyword] }
        set { descriptor[keyword] = newValue }
    }

    /// Whether the event is for this process: no address, kCurrentProcess,
    /// or this process's ID.
    public var isForCurrentProcess: Bool {
        guard let address, !address.isNull else { return true }
        if address.type == DescriptorType.processSerialNumber, let psn = address.load(as: (UInt32, UInt32).self) {
            return psn.0 == 0 && psn.1 == 2
        }
        if address.type == DescriptorType.kernelProcessID, let pid = address.load(as: Int32.self) {
            return pid == getpid()
        }
        return false
    }

    /// kCurrentProcess as a typeProcessSerialNumber address.
    public static var currentProcess: Descriptor {
        Descriptor(type: DescriptorType.processSerialNumber, bytes: withUnsafeBytes(of: (UInt32(0), UInt32(2))) { Array($0) })
    }

    /// A reply to an event: an Apple event of class 'aevt' and ID 'ansr'.
    public static func reply(to event: AppleEvent? = nil) -> AppleEvent {
        AppleEvent(eventClass: Core.eventClass, eventID: Core.answer, returnID: event?.returnID ?? 0)
    }

    public var returnID: Int16 { descriptor.attribute(Attribute.returnID)?.load(as: Int16.self) ?? 0 }
}
