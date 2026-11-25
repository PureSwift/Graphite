// Multiprocessing Services' event groups: 32 flags that senders set and a
// waiter takes, all at once, clearing them.

import GraphiteBase

/// An MPEventID.
public final class MPEvent: @unchecked Sendable {

    private let lock = ConditionLock()

    // The lock guards these.
    private var flags: UInt32 = 0
    private var deleted = false

    /// MPCreateEvent.
    public init() {}

    /// MPDeleteEvent: waiters are told kMPDeletedErr.
    public func delete() throws(MacError) {
        try lock.withLock { () throws(MacError) in
            guard !deleted else { throw .mpInvalidID }
            deleted = true
            lock.broadcast()
        }
    }

    /// MPSetEvent: adds flags to the event's.
    public func set(_ flags: UInt32) throws(MacError) {
        try lock.withLock { () throws(MacError) in
            guard !deleted else { throw .mpInvalidID }
            self.flags |= flags
            lock.signal()
        }
    }

    /// MPWaitForEvent: takes every flag set, waiting for one as long as
    /// `timeout` allows.
    public func wait(timeout: MacDuration = .forever) throws(MacError) -> UInt32 {
        let result: Result<UInt32, MacError>? = lock.withLock {
            guard !deleted else { return .failure(.mpInvalidID) }
            switch waitForMP(on: lock, timeout: timeout, until: { flags != 0 || deleted }) {
            case .terminated:
                return nil
            case .timedOut:
                return .failure(deleted ? .mpDeleted : .mpTimeout)
            case .ready:
                if deleted { return .failure(.mpDeleted) }
                let taken = flags
                flags = 0
                return .success(taken)
            }
        }
        return try finishWait(result)
    }
}
