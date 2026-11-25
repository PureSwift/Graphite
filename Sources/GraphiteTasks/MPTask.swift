// Multiprocessing Services' tasks: each a thread, which tells a queue when
// it ends, with two words it was made with and its result.
//
// A task told to terminate ends at its next wait on a queue, event,
// semaphore or critical region, or its next yield; a task that never waits
// on one runs to its end. Its queue is told at once, with the status
// MPTerminateTask was given.

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import GraphiteBase
import Synchronization

/// MPTaskID: a task's, or any thread's, identity.
public struct MPTaskID: Hashable, Sendable {

    public var rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
}

/// A Multiprocessing Services task.
public final class MPTask: Sendable {

    /// The work, whose result the queue is told.
    private let entry: @Sendable () -> Int32

    private let queue: MPQueue?

    private let terminationWords: (UInt, UInt)

    /// Whether the queue has been told the task ended.
    private let ended = Atomic<Bool>(false)

    private let terminating = Atomic<Bool>(false)

    /// The lock the task is waiting on, which terminating wakes.
    private let waitingOn = Mutex<ConditionLock?>(nil)

    private let weightValue = Atomic<UInt32>(100)

    public var id: MPTaskID { MPTaskID(rawValue: UInt(bitPattern: ObjectIdentifier(self))) }

    private init(entry: @escaping @Sendable () -> Int32, queue: MPQueue?, terminationWords: (UInt, UInt)) {
        self.entry = entry
        self.queue = queue
        self.terminationWords = terminationWords
    }

    /// MPCreateTask: starts the entry on a thread of its own. When it ends,
    /// `queue` is sent the termination words and its result.
    public static func create(queue: MPQueue? = nil,
                              terminationWords: (UInt, UInt) = (0, 0),
                              starter: ThreadStarter = .posix,
                              entry: @escaping @Sendable () -> Int32) throws(MacError) -> MPTask {
        let task = MPTask(entry: entry, queue: queue, terminationWords: terminationWords)
        guard starter.start({ task.main() }) else { throw .mpInsufficientResources }
        return task
    }

    private func main() {
        let retained = Unmanaged.passRetained(self)
        pthread_setspecific(currentTaskKey, retained.toOpaque())
        let result = entry()
        end(result)
        pthread_setspecific(currentTaskKey, nil)
        retained.release()
    }

    /// Tells the queue the task ended, once.
    private func end(_ result: Int32) {
        guard !ended.exchange(true, ordering: .sequentiallyConsistent) else { return }
        try? queue?.notify(terminationWords.0, terminationWords.1, UInt(bitPattern: Int(result)))
    }

    /// MPTerminateTask: ends the task at its next wait, telling its queue
    /// now, with `status`.
    public func terminate(status: Int32) throws(MacError) {
        guard !ended.load(ordering: .sequentiallyConsistent) else { throw .mpInvalidID }
        terminating.store(true, ordering: .sequentiallyConsistent)
        end(status)
        if let lock = waitingOn.withLock({ $0 }) {
            lock.withLock { lock.broadcast() }
        }
    }

    /// Whether the task has been told to end.
    public var isTerminating: Bool { terminating.load(ordering: .sequentiallyConsistent) }

    /// Whether the task's queue has been told it ended.
    public var hasEnded: Bool { ended.load(ordering: .sequentiallyConsistent) }

    /// MPSetTaskWeight: kept, as a scheduler hint the host has no use for.
    public var weight: UInt32 {
        get { weightValue.load(ordering: .relaxed) }
        set { weightValue.store(newValue, ordering: .relaxed) }
    }

    // MARK: - The current task

    /// The task the calling thread runs, if it is one.
    public static var current: MPTask? {
        guard let pointer = pthread_getspecific(currentTaskKey) else { return nil }
        return Unmanaged<MPTask>.fromOpaque(pointer).takeUnretainedValue()
    }

    /// MPCurrentTaskID: the running task's identity; a thread that is no
    /// task has one of its own all the same.
    public static var currentID: MPTaskID {
        if let task = current { return task.id }
        #if canImport(Darwin)
        return MPTaskID(rawValue: UInt(bitPattern: pthread_self()))
        #else
        return MPTaskID(rawValue: UInt(pthread_self()))
        #endif
    }

    /// MPYield: lets other threads run, and ends a task told to terminate.
    public static func yield() {
        exitIfTerminating()
        sched_yield()
    }

    /// MPExit: ends the calling task with its result. Its thread ends
    /// without returning through the frames below.
    public static func exit(status: Int32) -> Never {
        if let task = current {
            task.end(status)
            pthread_setspecific(currentTaskKey, nil)
            Unmanaged.passUnretained(task).release()
        }
        pthread_exit(nil)
    }

    /// Ends the calling task if it was told to terminate.
    static func exitIfTerminating() {
        if let task = current, task.isTerminating {
            exit(status: 0)
        }
    }

    /// Notes the lock the calling task waits on, so terminating can wake
    /// it; nil when it's done waiting.
    static func setWaiting(on lock: ConditionLock?) {
        current?.waitingOn.withLock { $0 = lock }
    }
}

/// The key of the thread-specific pointer to the running task.
private let currentTaskKey: pthread_key_t = {
    var key = pthread_key_t()
    pthread_key_create(&key, nil)
    return key
}()

// MARK: - Waits

enum WaitOutcome {
    case ready
    case timedOut
    case terminated
}

/// Waits, the lock held, until `ready` or the timeout, as every
/// Multiprocessing Services wait does. A task told to terminate stops
/// waiting.
func waitForMP(on lock: ConditionLock, timeout: MacDuration, until ready: () -> Bool) -> WaitOutcome {
    if ready() { return .ready }
    if timeout == .immediate { return .timedOut }
    let deadline = timeout.deadline
    MPTask.setWaiting(on: lock)
    defer { MPTask.setWaiting(on: nil) }
    while !ready() {
        if MPTask.current?.isTerminating == true { return .terminated }
        if !lock.wait(until: deadline) { return ready() ? .ready : .timedOut }
    }
    return .ready
}

/// A wait's result, once its lock is let go: a task told to terminate
/// ends here.
func finishWait<Value>(_ result: Result<Value, MacError>?) throws(MacError) -> Value {
    guard let result else {
        MPTask.exitIfTerminating()
        throw .mpTaskAborted
    }
    return try result.get()
}
