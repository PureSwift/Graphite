// Multiprocessing Services' critical regions: locks a task may enter again
// while it holds them, leaving as many times as it entered.

import GraphiteBase

/// An MPCriticalRegionID.
public final class MPCriticalRegion: @unchecked Sendable {

    private let lock = ConditionLock()

    // The lock guards these.
    private var owner: MPTaskID?
    private var depth = 0
    private var deleted = false

    /// MPCreateCriticalRegion.
    public init() {}

    /// MPDeleteCriticalRegion: waiters are told kMPDeletedErr.
    public func delete() throws(MacError) {
        try lock.withLock { () throws(MacError) in
            guard !deleted else { throw .mpInvalidID }
            deleted = true
            lock.broadcast()
        }
    }

    /// MPEnterCriticalRegion: enters, at once if the calling task holds
    /// the region, else waiting as long as `timeout` allows.
    public func enter(timeout: MacDuration = .forever) throws(MacError) {
        let caller = MPTask.currentID
        let result: Result<Void, MacError>? = lock.withLock {
            guard !deleted else { return .failure(.mpInvalidID) }
            switch waitForMP(on: lock, timeout: timeout, until: { owner == nil || owner == caller || deleted }) {
            case .terminated:
                return nil
            case .timedOut:
                return .failure(deleted ? .mpDeleted : .mpTimeout)
            case .ready:
                if deleted { return .failure(.mpDeleted) }
                owner = caller
                depth += 1
                return .success(())
            }
        }
        try finishWait(result)
    }

    /// MPExitCriticalRegion: leaves once; the region is free once the task
    /// has left as many times as it entered. paramErr from a task that
    /// doesn't hold it.
    public func exit() throws(MacError) {
        let caller = MPTask.currentID
        try lock.withLock { () throws(MacError) in
            guard !deleted else { throw .mpInvalidID }
            guard owner == caller, depth > 0 else { throw .parameter }
            depth -= 1
            if depth == 0 {
                owner = nil
                lock.broadcast()
            }
        }
    }

    /// Runs the body inside the region.
    public func withRegion<Result>(timeout: MacDuration = .forever, _ body: () throws -> Result) throws -> Result {
        try enter(timeout: timeout)
        defer { try? exit() }
        return try body()
    }
}
