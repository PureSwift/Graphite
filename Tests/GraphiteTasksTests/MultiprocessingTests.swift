import Synchronization
import Testing
import GraphiteBase
import GraphiteTasks

@Suite struct MPQueueTests {

    @Test func messagesComeInOrder() throws {
        let queue = MPQueue()
        for index in 0 ..< 100 { try queue.notify(UInt(index), 1, 2) }
        for index in 0 ..< 100 {
            #expect(try queue.wait(timeout: .immediate) == MPQueue.Message(UInt(index), 1, 2))
        }
    }

    @Test func orderPerSenderUnderContention() throws {
        let queue = MPQueue()
        let producers = 4, count = 2000
        for producer in 0 ..< producers {
            _ = try MPTask.create {
                for sequence in 0 ..< count { try? queue.notify(UInt(producer), UInt(sequence), 0) }
                return 0
            }
        }
        var next = [UInt](repeating: 0, count: producers)
        for _ in 0 ..< producers * count {
            let message = try queue.wait(timeout: .milliseconds(10_000))
            #expect(message.second == next[Int(message.first)])
            next[Int(message.first)] += 1
        }
        #expect(next == [UInt](repeating: UInt(count), count: producers))
    }

    @Test func timeouts() throws {
        let queue = MPQueue()
        #expect(throws: MacError.mpTimeout) { try queue.wait(timeout: .immediate) }
        let start = AbsoluteTime.now
        #expect(throws: MacError.mpTimeout) { try queue.wait(timeout: .milliseconds(20)) }
        #expect(AbsoluteTime.now - start >= 20_000_000)
        #expect(throws: MacError.mpTimeout) { try queue.wait(timeout: .microseconds(100)) }
    }

    @Test func deletingWakesWaiters() throws {
        let queue = MPQueue(), results = MPQueue()
        _ = try MPTask.create {
            do {
                _ = try queue.wait()
                try? results.notify(0, 0, 0)
            } catch {
                try? results.notify(UInt(bitPattern: Int((error as? MacError)?.code ?? -1)), 0, 0)
            }
            return 0
        }
        delay(until: .now + .milliseconds(20))
        try queue.delete()
        let result = try results.wait(timeout: .milliseconds(5000))
        #expect(Int32(truncatingIfNeeded: Int(bitPattern: result.first)) == MacError.mpDeleted.code)
        #expect(throws: MacError.mpInvalidID) { try queue.notify(0, 0, 0) }
        #expect(throws: MacError.mpInvalidID) { try queue.delete() }
        #expect(throws: MacError.mpInvalidID) { try queue.wait() }
    }
}

@Suite struct MPEventTests {

    @Test func flagsAccumulateAndClear() throws {
        let event = MPEvent()
        try event.set(0x1)
        try event.set(0x4)
        #expect(try event.wait(timeout: .immediate) == 0x5)
        #expect(throws: MacError.mpTimeout) { try event.wait(timeout: .immediate) }
    }

    @Test func waitsForASetter() throws {
        let event = MPEvent()
        _ = try MPTask.create {
            delay(until: .now + .milliseconds(10))
            try? event.set(0x80)
            return 0
        }
        #expect(try event.wait(timeout: .milliseconds(5000)) == 0x80)
        try event.delete()
        #expect(throws: MacError.mpInvalidID) { try event.set(1) }
    }
}

@Suite struct MPSemaphoreTests {

    @Test func countsToItsMaximum() throws {
        let semaphore = try MPSemaphore(maximum: 2, initial: 1)
        try semaphore.signal()
        #expect(throws: MacError.mpInsufficientResources) { try semaphore.signal() }
        #expect(semaphore.value == 2)
        try semaphore.wait(timeout: .immediate)
        try semaphore.wait(timeout: .immediate)
        #expect(throws: MacError.mpTimeout) { try semaphore.wait(timeout: .milliseconds(5)) }
        #expect(throws: MacError.parameter) { try MPSemaphore(maximum: 1, initial: 2) }
    }

    @Test func deletingWakesWaiters() throws {
        let semaphore = try MPSemaphore(maximum: 1, initial: 0)
        let results = MPQueue()
        _ = try MPTask.create {
            let code: Int32
            do {
                try semaphore.wait()
                code = 0
            } catch {
                code = (error as? MacError)?.code ?? -1
            }
            try? results.notify(UInt(bitPattern: Int(code)), 0, 0)
            return 0
        }
        delay(until: .now + .milliseconds(20))
        try semaphore.delete()
        let result = try results.wait(timeout: .milliseconds(5000))
        #expect(Int32(truncatingIfNeeded: Int(bitPattern: result.first)) == MacError.mpDeleted.code)
    }
}

@Suite struct MPCriticalRegionTests {

    @Test func recursivePerTask() throws {
        let region = MPCriticalRegion()
        try region.enter(timeout: .immediate)
        try region.enter(timeout: .immediate)
        let results = MPQueue()
        // Another task can't enter while this one holds it, nor leave it.
        _ = try MPTask.create {
            var codes: [Int32] = []
            do { try region.enter(timeout: .milliseconds(20)) } catch { codes.append((error as? MacError)?.code ?? -1) }
            do { try region.exit() } catch { codes.append((error as? MacError)?.code ?? -1) }
            try? results.notify(UInt(bitPattern: Int(codes[0])), UInt(bitPattern: Int(codes[1])), 0)
            return 0
        }
        let result = try results.wait(timeout: .milliseconds(5000))
        #expect(Int32(truncatingIfNeeded: Int(bitPattern: result.first)) == MacError.mpTimeout.code)
        #expect(Int32(truncatingIfNeeded: Int(bitPattern: result.second)) == MacError.parameter.code)
        try region.exit()
        try region.exit()
        #expect(throws: MacError.parameter) { try region.exit() }

        // Free now: another task enters.
        _ = try MPTask.create {
            let entered = (try? region.enter(timeout: .milliseconds(1000))) != nil
            if entered { try? region.exit() }
            try? results.notify(entered ? 1 : 0, 0, 0)
            return 0
        }
        #expect(try results.wait(timeout: .milliseconds(5000)).first == 1)
    }

    @Test func mutualExclusion() throws {
        let region = MPCriticalRegion()
        let inside = Atomic<Int>(0), overlapped = Atomic<Bool>(false)
        let done = MPQueue()
        for _ in 0 ..< 4 {
            _ = try MPTask.create(queue: done) {
                for _ in 0 ..< 200 {
                    try? region.enter()
                    if inside.add(1, ordering: .sequentiallyConsistent).newValue > 1 {
                        overlapped.store(true, ordering: .sequentiallyConsistent)
                    }
                    MPTask.yield()
                    inside.subtract(1, ordering: .sequentiallyConsistent)
                    try? region.exit()
                }
                return 0
            }
        }
        for _ in 0 ..< 4 { _ = try done.wait(timeout: .milliseconds(10_000)) }
        let overlappedValue = overlapped.load(ordering: .sequentiallyConsistent)
        #expect(!overlappedValue)
    }
}

@Suite struct MPTaskTests {

    @Test func queueIsToldOfTheEnd() throws {
        let queue = MPQueue()
        let task = try MPTask.create(queue: queue, terminationWords: (7, 8)) { 42 }
        let message = try queue.wait(timeout: .milliseconds(5000))
        #expect(message == MPQueue.Message(7, 8, 42))
        #expect(task.hasEnded)
        #expect(throws: MacError.mpInvalidID) { try task.terminate(status: 1) }
    }

    @Test func negativeResults() throws {
        let queue = MPQueue()
        _ = try MPTask.create(queue: queue) { -1 }
        let message = try queue.wait(timeout: .milliseconds(5000))
        #expect(Int32(truncatingIfNeeded: Int(bitPattern: message.third)) == -1)
    }

    @Test func currentTask() throws {
        let queue = MPQueue(), results = MPQueue()
        #expect(MPTask.current == nil)
        let outside = MPTask.currentID
        #expect(outside == MPTask.currentID)
        let task = try MPTask.create(queue: queue) {
            let id = MPTask.current?.id
            try? results.notify(id?.rawValue ?? 0, MPTask.currentID.rawValue, 0)
            return 0
        }
        let message = try results.wait(timeout: .milliseconds(5000))
        #expect(message.first == task.id.rawValue)
        #expect(message.second == task.id.rawValue)
        #expect(task.id != outside)
        _ = try queue.wait(timeout: .milliseconds(5000))
    }

    @Test func exitEndsTheTaskWithItsStatus() throws {
        let queue = MPQueue()
        _ = try MPTask.create(queue: queue, terminationWords: (1, 2)) {
            MPTask.exit(status: 99)
        }
        let message = try queue.wait(timeout: .milliseconds(5000))
        #expect(message == MPQueue.Message(1, 2, 99))
    }

    @Test func terminatingATaskThatWaits() throws {
        let queue = MPQueue(), never = MPQueue()
        let returned = Atomic<Bool>(false)
        let task = try MPTask.create(queue: queue, terminationWords: (3, 4)) {
            _ = try? never.wait()
            returned.store(true, ordering: .sequentiallyConsistent)
            return 0
        }
        delay(until: .now + .milliseconds(20))
        try task.terminate(status: -5)
        let message = try queue.wait(timeout: .milliseconds(5000))
        #expect(message == MPQueue.Message(3, 4, UInt(bitPattern: -5)))
        #expect(task.isTerminating)
        delay(until: .now + .milliseconds(20))
        let returnedValue = returned.load(ordering: .sequentiallyConsistent)
        #expect(!returnedValue)
        // Told once.
        #expect(throws: MacError.mpTimeout) { try queue.wait(timeout: .milliseconds(20)) }
    }

    @Test func weight() throws {
        let task = try MPTask.create { 0 }
        task.weight = 200
        #expect(task.weight == 200)
    }

    @Test func threadStarterIsUsed() throws {
        let started = Atomic<Int>(0)
        let starter = ThreadStarter { body in
            started.add(1, ordering: .sequentiallyConsistent)
            return ThreadStarter.posix.start(body)
        }
        let queue = MPQueue()
        _ = try MPTask.create(queue: queue, starter: starter) { 0 }
        _ = try queue.wait(timeout: .milliseconds(5000))
        let startedValue = started.load(ordering: .sequentiallyConsistent)
        #expect(startedValue == 1)
        let failing = ThreadStarter { _ in false }
        #expect(throws: MacError.mpInsufficientResources) { try MPTask.create(starter: failing) { 0 } }
    }
}

@Suite struct AtomicMemoryAcrossTasksTests {

    @Test func concurrentIncrements() throws {
        let value = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        defer { value.deallocate() }
        value.initialize(to: 0)
        let address = UInt(bitPattern: value)
        let done = MPQueue()
        for _ in 0 ..< 8 {
            _ = try MPTask.create(queue: done) {
                let value = UnsafeMutablePointer<Int32>(bitPattern: address)!
                for _ in 0 ..< 10_000 { AtomicMemory.increment(value) }
                return 0
            }
        }
        for _ in 0 ..< 8 { _ = try done.wait(timeout: .milliseconds(10_000)) }
        #expect(value.pointee == 80_000)
    }
}

@Suite struct MPMemoryTests {

    @Test func alignedAndCleared() throws {
        for log2 in [UInt8(0), 4, 6, 12] {
            let block = try #require(MPMemory.allocate(size: 100, alignmentLog2: log2, clear: true))
            #expect(UInt(bitPattern: block) % UInt(1 << max(Int(log2), 4)) == 0)
            #expect(UnsafeRawBufferPointer(start: block, count: 100).allSatisfy { $0 == 0 })
            MPMemory.free(block)
        }
        MPMemory.free(nil)
    }
}
