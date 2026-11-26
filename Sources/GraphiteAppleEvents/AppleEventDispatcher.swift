// The application's Apple Event handlers, by class and ID, and the events it
// sends: those for this process go straight to its handlers; no other
// process receives them, so one for another fails as one that isn't
// running would.

import Synchronization
import GraphiteBase

public final class AppleEventDispatcher: Sendable {

    /// A handler: it reads the event and fills in the reply, and throws
    /// the result it returns otherwise.
    public typealias Handler = @Sendable (AppleEvent, inout Descriptor) throws(MacError) -> Void

    /// An installed handler.
    public struct Entry: Sendable {

        public var eventClass: FourCharCode

        public var eventID: FourCharCode

        /// Installed in the system's table rather than the application's.
        public var isSystem: Bool

        /// The host's own: a procedure's address, say, which
        /// AEGetEventHandler gives back and AERemoveEventHandler matches.
        public var procedure: UInt

        /// The host's own: the reference constant installed with it.
        public var referenceConstant: UInt

        public var handler: Handler

        public init(eventClass: FourCharCode, eventID: FourCharCode, isSystem: Bool = false, procedure: UInt = 0,
                    referenceConstant: UInt = 0, handler: @escaping Handler) {
            self.eventClass = eventClass
            self.eventID = eventID
            self.isSystem = isSystem
            self.procedure = procedure
            self.referenceConstant = referenceConstant
            self.handler = handler
        }
    }

    /// AESend's modes.
    public struct SendMode: OptionSet, Sendable {
        public var rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }

        /// kAENoReply.
        public static var noReply: SendMode { SendMode(rawValue: 1) }
        /// kAEQueueReply.
        public static var queueReply: SendMode { SendMode(rawValue: 2) }
        /// kAEWaitReply.
        public static var waitReply: SendMode { SendMode(rawValue: 3) }

        /// Whether the sender waits for the reply.
        public var waitsForReply: Bool { rawValue & 3 == 3 }
    }

    private let entries = Mutex<[Entry]>([])

    public let coercions: CoercionTable

    public init(coercions: CoercionTable = CoercionTable()) {
        self.coercions = coercions
    }

    // MARK: Handlers

    /// AEInstallEventHandler: replaces one of the same class and ID in the
    /// same table.
    public func install(_ entry: Entry) {
        entries.withLock { entries in
            entries.removeAll { $0.eventClass == entry.eventClass && $0.eventID == entry.eventID && $0.isSystem == entry.isSystem }
            entries.append(entry)
        }
    }

    /// AERemoveEventHandler: errAEHandlerNotFound if none of the class and
    /// ID is installed in the table, or none of the procedure when one is
    /// given.
    public func remove(eventClass: FourCharCode, eventID: FourCharCode, procedure: UInt? = nil, isSystem: Bool = false) throws(MacError) {
        let removed = entries.withLock { entries in
            let before = entries.count
            entries.removeAll {
                $0.eventClass == eventClass && $0.eventID == eventID && $0.isSystem == isSystem && (procedure == nil || procedure == 0 || $0.procedure == procedure)
            }
            return entries.count < before
        }
        guard removed else { throw .handlerNotFound }
    }

    /// AEGetEventHandler: the handler installed for exactly the class and
    /// ID.
    public func entry(eventClass: FourCharCode, eventID: FourCharCode, isSystem: Bool = false) -> Entry? {
        entries.withLock { $0.first { $0.eventClass == eventClass && $0.eventID == eventID && $0.isSystem == isSystem } }
    }

    /// The handler an event goes to: the application's for its class and
    /// ID, else the system's, else one with typeWildCard for either.
    public func handler(eventClass: FourCharCode, eventID: FourCharCode) -> Entry? {
        entries.withLock { entries in
            let ordered = entries.filter { !$0.isSystem } + entries.filter(\.isSystem)
            return ordered.first { $0.eventClass == eventClass && $0.eventID == eventID }
                ?? ordered.first {
                    ($0.eventClass == eventClass || $0.eventClass == DescriptorType.wildCard)
                        && ($0.eventID == eventID || $0.eventID == DescriptorType.wildCard)
                }
        }
    }

    // MARK: Dispatching

    /// AEProcessAppleEvent's and AEResumeTheCurrentEvent's work: hands an
    /// event to its handler, with a reply it fills in. errAEEventNotHandled
    /// if there is none.
    public func dispatch(_ event: AppleEvent, reply: inout Descriptor) throws(MacError) {
        guard let entry = handler(eventClass: event.eventClass, eventID: event.eventID) else { throw .eventNotHandled }
        try entry.handler(event, &reply)
    }

    /// AESend: an event for this process goes to its handler at once. The
    /// reply is an 'aevt'\'ansr' event when the sender waits for one, with
    /// the handler's error number in it if it failed; else typeNull.
    /// procNotFound for an event for another process; errAEEventNotHandled
    /// only when the sender waits and no handler took it.
    @discardableResult
    public func send(_ event: AppleEvent, mode: SendMode = .noReply) throws(MacError) -> Descriptor {
        var reply = mode.waitsForReply ? AppleEvent.reply(to: event).descriptor : Descriptor.null
        guard event.isForCurrentProcess else { throw .processNotFound }
        do {
            try dispatch(event, reply: &reply)
        } catch {
            if mode.waitsForReply {
                if reply[AppleEvent.Parameter.errorNumber] == nil { reply[AppleEvent.Parameter.errorNumber] = Descriptor(error.code) }
                if error == .eventNotHandled { throw error }
            }
        }
        return reply
    }

    /// Sends one of the required events to the application, from the
    /// system: false if no handler takes it, so the caller can do what the
    /// system does without one (a quit with no handler quits).
    @discardableResult
    public func sendCoreEvent(_ eventID: FourCharCode, directObject: Descriptor? = nil) -> Bool {
        guard handler(eventClass: AppleEvent.Core.eventClass, eventID: eventID) != nil else { return false }
        var event = AppleEvent(eventClass: AppleEvent.Core.eventClass, eventID: eventID, target: AppleEvent.currentProcess)
        if let directObject { event[parameter: AppleEvent.Parameter.directObject] = directObject }
        var reply = Descriptor.null
        try? dispatch(event, reply: &reply)
        return true
    }

    /// 'odoc' or 'pdoc' for files, as a list of descriptors of a file type.
    @discardableResult
    public func sendOpenDocuments(_ paths: [String], print: Bool = false, as type: FourCharCode = DescriptorType.fileURL) -> Bool {
        var list = Descriptor.list()
        for path in paths {
            guard let file = try? coercions.coerce(FileURLCoding().descriptor(forPath: path) ?? .null, to: type) else { continue }
            list.items.append(Descriptor.Item(descriptor: file))
        }
        return sendCoreEvent(print ? AppleEvent.Core.printDocuments : AppleEvent.Core.openDocuments, directObject: list)
    }
}
