// The Time Manager: tasks a program installs and primes to run once after
// a delay, each time they're primed. Mac OS X runs them on a thread of
// their own, apart from the program's; so does Graphite, one thread for
// every task, in the order they come due. RAD's Bink decodes and reads its
// movies from them.
//
// An extended task (InsXTime) primed again from its own action counts the
// delay from when it was due, not from when it ran, so a periodic task
// doesn't drift.

import GraphiteBase

/// A Time Manager task (a TMTask record's behavior).
public final class TimeManagerTask: @unchecked Sendable {

    /// The task's work, run on the Time Manager's thread with the task.
    public let action: @Sendable (TimeManagerTask) -> Void

    /// Whether it was installed as an extended task, with InsXTime or
    /// InstallXTimeTask.
    public let isExtended: Bool

    // The scheduler's lock guards these.

    /// When an extended task was last due (tmWakeUp); nil before it is
    /// first primed.
    private var wakeUp: UInt64?

    private var isInstalledValue = false

    public init(extended: Bool = false, action: @escaping @Sendable (TimeManagerTask) -> Void) {
        self.isExtended = extended
        self.action = action
    }

    /// InsTime, InsXTime, InstallTimeTask, InstallXTimeTask: readies the
    /// task. It runs once primed.
    public func install() {
        TimeManagerScheduler.shared.withLock {
            isInstalledValue = true
            wakeUp = nil
        }
    }

    /// When an extended task was last due (tmWakeUp), which each prime
    /// from its action counts from; nil for a plain task, or before it is
    /// first primed.
    public var wakeUpTime: AbsoluteTime? {
        TimeManagerScheduler.shared.withLock { wakeUp.map { AbsoluteTime(nanoseconds: $0) } }
    }

    public var isInstalled: Bool {
        TimeManagerScheduler.shared.withLock { isInstalledValue }
    }

    /// Whether the task is waiting to run.
    public var isPrimed: Bool {
        TimeManagerScheduler.shared.isPrimed(self)
    }

    /// PrimeTime: runs the task once after `count` milliseconds, or
    /// -`count` microseconds, in place of any time it was primed for.
    public func prime(_ count: Int32) {
        let delay = count >= 0 ? UInt64(count) * 1_000_000 : UInt64(count.magnitude) * 1000
        TimeManagerScheduler.shared.prime(self) { now in
            let start = isExtended ? (wakeUp ?? now) : now
            let due = start &+ delay
            if isExtended { wakeUp = due }
            return due
        }
    }

    /// RmvTime and RemoveTimeTask: takes the task out, and returns what was
    /// left of its time: milliseconds, or negative microseconds under one
    /// (tmCount); zero if it wasn't primed.
    @discardableResult
    public func remove() -> Int32 {
        let left = TimeManagerScheduler.shared.unprime(self)
        TimeManagerScheduler.shared.withLock { isInstalledValue = false }
        guard let left, left > 0 else { return 0 }
        return left >= 1_000_000 ? Int32(clamping: left / 1_000_000) : -Int32(left / 1000)
    }
}

/// The Time Manager's thread and its queue of primed tasks.
final class TimeManagerScheduler: @unchecked Sendable {

    static let shared = TimeManagerScheduler()

    private struct Primed {
        let task: TimeManagerTask
        let due: UInt64
        let order: UInt64
    }

    private let lock = ConditionLock()

    private var queue: [Primed] = []

    private var nextOrder: UInt64 = 0

    private var started = false

    func withLock<Result>(_ body: () -> Result) -> Result {
        lock.withLock(body)
    }

    func isPrimed(_ task: TimeManagerTask) -> Bool {
        lock.withLock { queue.contains { $0.task === task } }
    }

    /// Queues the task at the time `due` gives, the lock held, from now.
    func prime(_ task: TimeManagerTask, due: (UInt64) -> UInt64) {
        lock.withLock {
            if !started {
                started = startPOSIXThread { TimeManagerScheduler.shared.run() }
            }
            queue.removeAll { $0.task === task }
            queue.append(Primed(task: task, due: due(SystemClock.nanoseconds), order: nextOrder))
            nextOrder += 1
            lock.signal()
        }
    }

    /// Takes the task out of the queue; the nanoseconds it had left, or nil
    /// if it wasn't there.
    func unprime(_ task: TimeManagerTask) -> UInt64? {
        lock.withLock {
            guard let index = queue.firstIndex(where: { $0.task === task }) else { return nil }
            let primed = queue.remove(at: index)
            let now = SystemClock.nanoseconds
            return primed.due > now ? primed.due - now : 0
        }
    }

    private func run() {
        lock.lock()
        while true {
            guard let index = queue.indices.min(by: { (queue[$0].due, queue[$0].order) < (queue[$1].due, queue[$1].order) }) else {
                lock.wait(until: nil)
                continue
            }
            if SystemClock.nanoseconds < queue[index].due {
                lock.wait(until: queue[index].due)
                continue
            }
            let task = queue.remove(at: index).task
            // The action runs without the lock: it may prime itself again.
            lock.unlock()
            task.action(task)
            lock.lock()
        }
    }
}
