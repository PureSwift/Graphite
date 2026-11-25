// A mutex with a condition variable, for the waits of Multiprocessing
// Services and the Time Manager's thread. Deadlines are nanoseconds of the
// monotonic clock, so changing the wall clock doesn't stretch or cut a
// wait.

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import GraphiteBase

final class ConditionLock: @unchecked Sendable {

    private let mutex: UnsafeMutablePointer<pthread_mutex_t>

    private let condition: UnsafeMutablePointer<pthread_cond_t>

    init() {
        mutex = .allocate(capacity: 1)
        mutex.initialize(to: pthread_mutex_t())
        pthread_mutex_init(mutex, nil)
        condition = .allocate(capacity: 1)
        condition.initialize(to: pthread_cond_t())
        #if canImport(Darwin)
        pthread_cond_init(condition, nil)
        #else
        var attributes = pthread_condattr_t()
        pthread_condattr_init(&attributes)
        pthread_condattr_setclock(&attributes, CLOCK_MONOTONIC)
        pthread_cond_init(condition, &attributes)
        pthread_condattr_destroy(&attributes)
        #endif
    }

    deinit {
        pthread_cond_destroy(condition)
        condition.deallocate()
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }

    func lock() {
        pthread_mutex_lock(mutex)
    }

    func unlock() {
        pthread_mutex_unlock(mutex)
    }

    func withLock<Result, Failure: Error>(_ body: () throws(Failure) -> Result) throws(Failure) -> Result {
        lock()
        defer { unlock() }
        return try body()
    }

    func signal() {
        pthread_cond_signal(condition)
    }

    func broadcast() {
        pthread_cond_broadcast(condition)
    }

    /// Waits, the lock held, for a signal or the deadline (nil for none).
    /// False once the deadline has passed. Like any condition wait, it may
    /// return early: callers check what they wait for and wait again.
    @discardableResult
    func wait(until deadline: UInt64?) -> Bool {
        guard let deadline else {
            pthread_cond_wait(condition, mutex)
            return true
        }
        let now = SystemClock.nanoseconds
        guard now < deadline else { return false }
        #if canImport(Darwin)
        let remaining = deadline - now
        var interval = timespec(tv_sec: time_t(remaining / 1_000_000_000), tv_nsec: Int(remaining % 1_000_000_000))
        _ = pthread_cond_timedwait_relative_np(condition, mutex, &interval)
        #else
        var until = timespec(tv_sec: time_t(deadline / 1_000_000_000), tv_nsec: Int(deadline % 1_000_000_000))
        _ = pthread_cond_timedwait(condition, mutex, &until)
        #endif
        return SystemClock.nanoseconds < deadline
    }
}
