import Synchronization
import Testing
import GraphiteBase
import GraphiteTasks

@Suite struct TimeManagerTests {

    @Test func tasksRunInTheOrderTheyComeDue() throws {
        let order = Mutex<[Int]>([])
        let done = try MPSemaphore(maximum: 3, initial: 0)
        let tasks = [30, 10, 20].enumerated().map { index, delay in
            let task = TimeManagerTask { _ in
                order.withLock { $0.append(index) }
                try? done.signal()
            }
            task.install()
            return (task, Int32(delay))
        }
        for (task, delay) in tasks { task.prime(delay) }
        for _ in 0 ..< 3 { try done.wait(timeout: .milliseconds(5000)) }
        let ran = order.withLock { $0 }
        #expect(ran == [1, 2, 0])
    }

    @Test func microsecondDelays() throws {
        let done = try MPSemaphore(maximum: 1, initial: 0)
        let task = TimeManagerTask { _ in try? done.signal() }
        task.install()
        task.prime(-500)
        try done.wait(timeout: .milliseconds(5000))
    }

    /// Ten periods of 20 ms, each run taking 10 ms before priming again: an
    /// extended task counts each period from when it was due, so its due
    /// times are exactly 20 ms apart however late it runs; a plain one
    /// counts from when it ran, and takes at least 300 ms. Only lower
    /// bounds are on the clock: a busy machine wakes late, never early.
    @Test(arguments: [true, false])
    func extendedTasksDontDrift(extended: Bool) throws {
        let runs = Atomic<Int>(0)
        let wakeUps = Mutex<[UInt64]>([])
        let done = try MPSemaphore(maximum: 1, initial: 0)
        let task = TimeManagerTask(extended: extended) { task in
            if let wakeUp = task.wakeUpTime { wakeUps.withLock { $0.append(wakeUp.nanoseconds) } }
            if runs.add(1, ordering: .sequentiallyConsistent).newValue == 10 {
                try? done.signal()
                return
            }
            delay(until: .now + .milliseconds(10))
            task.prime(20)
        }
        task.install()
        let start = AbsoluteTime.now
        task.prime(20)
        try done.wait(timeout: .milliseconds(10_000))
        let elapsed = (AbsoluteTime.now - start) / 1_000_000
        let due = wakeUps.withLock { $0 }
        if extended {
            #expect(due.count == 10)
            #expect(zip(due, due.dropFirst()).allSatisfy { $1 - $0 == 20_000_000 }, "\(due)")
            #expect(elapsed >= 200, "\(elapsed) ms")
        } else {
            #expect(due.isEmpty)
            #expect(elapsed >= 300, "\(elapsed) ms")
        }
    }

    @Test func removingReturnsTimeLeft() throws {
        let ran = Atomic<Bool>(false)
        let task = TimeManagerTask { _ in ran.store(true, ordering: .sequentiallyConsistent) }
        task.install()
        #expect(task.isInstalled)
        task.prime(1000)
        #expect(task.isPrimed)
        let left = task.remove()
        #expect(left > 900 && left <= 1000)
        #expect(!task.isPrimed)
        #expect(!task.isInstalled)
        #expect(task.remove() == 0)
        delay(until: .now + .milliseconds(20))
        let ranValue = ran.load(ordering: .sequentiallyConsistent)
        #expect(!ranValue)
    }

    @Test func primingAgainReplacesTheTime() throws {
        let runs = Atomic<Int>(0)
        let done = try MPSemaphore(maximum: 2, initial: 0)
        let task = TimeManagerTask { _ in
            runs.add(1, ordering: .sequentiallyConsistent)
            try? done.signal()
        }
        task.install()
        task.prime(5000)
        task.prime(5)
        try done.wait(timeout: .milliseconds(2000))
        delay(until: .now + .milliseconds(30))
        let runsValue = runs.load(ordering: .sequentiallyConsistent)
        #expect(runsValue == 1)
        task.remove()
    }
}
