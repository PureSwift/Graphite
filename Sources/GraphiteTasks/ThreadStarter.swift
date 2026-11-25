// How Graphite starts the threads that run Multiprocessing Services' tasks.
// Linux programs use POSIX threads as they are; Perry starts them through
// the program's own libSystem, so a task's thread is set up as the
// program's threads are.

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// Starts a thread that runs a closure, detached.
public struct ThreadStarter: Sendable {

    /// Starts the body on a new thread; whether it could.
    public var start: @Sendable (_ body: @escaping @Sendable () -> Void) -> Bool

    public init(start: @escaping @Sendable (_ body: @escaping @Sendable () -> Void) -> Bool) {
        self.start = start
    }

    /// The C library's POSIX threads.
    public static var posix: ThreadStarter {
        ThreadStarter { body in startPOSIXThread(body) }
    }
}

private final class ThreadBody {

    let body: @Sendable () -> Void

    init(_ body: @escaping @Sendable () -> Void) {
        self.body = body
    }
}

/// A detached POSIX thread that runs the body.
func startPOSIXThread(_ body: @escaping @Sendable () -> Void) -> Bool {
    let context = Unmanaged.passRetained(ThreadBody(body)).toOpaque()
    #if canImport(Darwin)
    var thread: pthread_t?
    let error = pthread_create(&thread, nil, { context in
        Unmanaged<ThreadBody>.fromOpaque(context).takeRetainedValue().body()
        return nil
    }, context)
    if error == 0, let thread { pthread_detach(thread) }
    #else
    var thread = pthread_t()
    let error = pthread_create(&thread, nil, { context in
        Unmanaged<ThreadBody>.fromOpaque(context!).takeRetainedValue().body()
        return nil
    }, context)
    if error == 0 { pthread_detach(thread) }
    #endif
    if error != 0 { Unmanaged<ThreadBody>.fromOpaque(context).release() }
    return error == 0
}
