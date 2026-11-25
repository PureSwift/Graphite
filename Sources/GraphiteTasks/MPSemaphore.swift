// Multiprocessing Services' counting semaphores, with a maximum count: a
// signal past it is refused. A binary semaphore has a maximum of one.

import GraphiteBase

/// An MPSemaphoreID.
public final class MPSemaphore: @unchecked Sendable {

    public let maximum: UInt32

    private let lock = ConditionLock()

    // The lock guards these.
    private var count: UInt32
    private var deleted = false

    /// MPCreateSemaphore: a semaphore at `initial`, at most `maximum`.
    public init(maximum: UInt32, initial: UInt32) throws(MacError) {
        guard maximum > 0, initial <= maximum else { throw .parameter }
        self.maximum = maximum
        self.count = initial
    }

    /// MPDeleteSemaphore: waiters are told kMPDeletedErr.
    public func delete() throws(MacError) {
        try lock.withLock { () throws(MacError) in
            guard !deleted else { throw .mpInvalidID }
            deleted = true
            lock.broadcast()
        }
    }

    /// MPSignalSemaphore: one more, or kMPInsufficientResourcesErr at the
    /// maximum.
    public func signal() throws(MacError) {
        try lock.withLock { () throws(MacError) in
            guard !deleted else { throw .mpInvalidID }
            guard count < maximum else { throw .mpInsufficientResources }
            count += 1
            lock.signal()
        }
    }

    /// MPWaitOnSemaphore: one less, waiting for one as long as `timeout`
    /// allows.
    public func wait(timeout: MacDuration = .forever) throws(MacError) {
        let result: Result<Void, MacError>? = lock.withLock {
            guard !deleted else { return .failure(.mpInvalidID) }
            switch waitForMP(on: lock, timeout: timeout, until: { count > 0 || deleted }) {
            case .terminated:
                return nil
            case .timedOut:
                return .failure(deleted ? .mpDeleted : .mpTimeout)
            case .ready:
                if deleted { return .failure(.mpDeleted) }
                count -= 1
                return .success(())
            }
        }
        try finishWait(result)
    }

    /// The count now.
    public var value: UInt32 {
        lock.withLock { count }
    }
}
