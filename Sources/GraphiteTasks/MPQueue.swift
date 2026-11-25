// Multiprocessing Services' message queues: messages of three words,
// waited for in the order they were sent.

import GraphiteBase

/// An MPQueue.
public final class MPQueue: @unchecked Sendable {

    /// A message: three words, which a program fills with pointers or
    /// numbers.
    public struct Message: Hashable, Sendable {
        public var first: UInt
        public var second: UInt
        public var third: UInt

        public init(_ first: UInt, _ second: UInt, _ third: UInt) {
            self.first = first
            self.second = second
            self.third = third
        }
    }

    private let lock = ConditionLock()

    // The lock guards these.
    private var messages: [Message] = []
    private var head = 0
    private var deleted = false
    private var reserve = 0

    /// MPCreateQueue.
    public init() {}

    /// MPDeleteQueue: waiters are told kMPDeletedErr, and the queue is no
    /// longer valid.
    public func delete() throws(MacError) {
        try lock.withLock { () throws(MacError) in
            guard !deleted else { throw .mpInvalidID }
            deleted = true
            messages.removeAll()
            head = 0
            lock.broadcast()
        }
    }

    /// MPSetQueueReserve: kept; messages are allocated as they're sent.
    public func setReserve(_ count: Int) throws(MacError) {
        try lock.withLock { () throws(MacError) in
            guard !deleted else { throw .mpInvalidID }
            reserve = count
        }
    }

    /// MPNotifyQueue: sends a message.
    public func notify(_ message: Message) throws(MacError) {
        try lock.withLock { () throws(MacError) in
            guard !deleted else { throw .mpInvalidID }
            messages.append(message)
            lock.signal()
        }
    }

    public func notify(_ first: UInt, _ second: UInt, _ third: UInt) throws(MacError) {
        try notify(Message(first, second, third))
    }

    /// MPWaitOnQueue: the next message, waiting as long as `timeout`
    /// allows: kMPTimeoutErr when no message came, kMPDeletedErr when the
    /// queue was deleted.
    public func wait(timeout: MacDuration = .forever) throws(MacError) -> Message {
        let result: Result<Message, MacError>? = lock.withLock {
            guard !deleted else { return .failure(.mpInvalidID) }
            switch waitForMP(on: lock, timeout: timeout, until: { head < messages.count || deleted }) {
            case .terminated:
                return nil
            case .timedOut:
                return .failure(deleted ? .mpDeleted : .mpTimeout)
            case .ready:
                if deleted { return .failure(.mpDeleted) }
                let message = messages[head]
                head += 1
                if head > 64, head * 2 > messages.count {
                    messages.removeFirst(head)
                    head = 0
                }
                return .success(message)
            }
        }
        return try finishWait(result)
    }
}
