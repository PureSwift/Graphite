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

    /// Ten periods of 10 ms, each run taking 5 ms before priming again: an
    /// extended task counts from when it was due and takes 100 ms; a plain
    /// one counts from when it ran, and takes at least 150.
    @Test(arguments: [true, false])
    func extendedTasksDontDrift(extended: Bool) throws {
        let runs = Atomic<Int>(0)
        let done = try MPSemaphore(maximum: 1, initial: 0)
        let task = TimeManagerTask(extended: extended) { task in
            if runs.add(1, ordering: .sequentiallyConsistent).newValue == 10 {
                try? done.signal()
                return
            }
            delay(until: .now + .milliseconds(5))
            task.prime(10)
        }
        task.install()
        let start = AbsoluteTime.now
        task.prime(10)
        try done.wait(timeout: .milliseconds(10_000))
        let elapsed = (AbsoluteTime.now - start) / 1_000_000
        if extended {
            #expect(elapsed >= 100 && elapsed < 145, "\(elapsed) ms")
        } else {
            #expect(elapsed >= 145, "\(elapsed) ms")
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
