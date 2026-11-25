// Atomic arithmetic on a program's own memory, as Open Transport's
// OTAtomicAdd32 and OTAtomicAdd16 and Driver Services' CompareAndSwap,
// IncrementAtomic and DecrementAtomic do it: sequentially consistent, with
// the Synchronization module's atomics over the integers where the program
// keeps them.

import Synchronization

/// Atomic operations on integers in memory Graphite doesn't own. Each
/// pointer must be aligned to its integer's size.
public enum AtomicMemory {

    /// OTAtomicAdd32: adds and returns the new value.
    @discardableResult
    public static func add(_ amount: Int32, to value: UnsafeMutablePointer<Int32>) -> Int32 {
        atomic(value, as: Atomic<Int32>.self).pointee.wrappingAdd(amount, ordering: .sequentiallyConsistent).newValue
    }

    /// OTAtomicAdd16: adds and returns the new value.
    @discardableResult
    public static func add(_ amount: Int16, to value: UnsafeMutablePointer<Int16>) -> Int16 {
        atomic(value, as: Atomic<Int16>.self).pointee.wrappingAdd(amount, ordering: .sequentiallyConsistent).newValue
    }

    /// IncrementAtomic: adds one and returns the value before.
    @discardableResult
    public static func increment(_ value: UnsafeMutablePointer<Int32>) -> Int32 {
        atomic(value, as: Atomic<Int32>.self).pointee.wrappingAdd(1, ordering: .sequentiallyConsistent).oldValue
    }

    /// DecrementAtomic: takes one away and returns the value before.
    @discardableResult
    public static func decrement(_ value: UnsafeMutablePointer<Int32>) -> Int32 {
        atomic(value, as: Atomic<Int32>.self).pointee.wrappingSubtract(1, ordering: .sequentiallyConsistent).oldValue
    }

    /// CompareAndSwap: stores `new` if the value is `old`; whether it did.
    @discardableResult
    public static func compareAndSwap(_ old: UInt32, _ new: UInt32, at value: UnsafeMutablePointer<UInt32>) -> Bool {
        atomic(value, as: Atomic<UInt32>.self).pointee
            .compareExchange(expected: old, desired: new, ordering: .sequentiallyConsistent).exchanged
    }

    /// BitOr, BitAnd and BitXor's atomic forms (OTAtomicSetBit and the
    /// rest build on these): applies the mask and returns the value before.
    @discardableResult
    public static func or(_ mask: UInt32, into value: UnsafeMutablePointer<UInt32>) -> UInt32 {
        atomic(value, as: Atomic<UInt32>.self).pointee.bitwiseOr(mask, ordering: .sequentiallyConsistent).oldValue
    }

    @discardableResult
    public static func and(_ mask: UInt32, into value: UnsafeMutablePointer<UInt32>) -> UInt32 {
        atomic(value, as: Atomic<UInt32>.self).pointee.bitwiseAnd(mask, ordering: .sequentiallyConsistent).oldValue
    }

    @discardableResult
    public static func xor(_ mask: UInt32, into value: UnsafeMutablePointer<UInt32>) -> UInt32 {
        atomic(value, as: Atomic<UInt32>.self).pointee.bitwiseXor(mask, ordering: .sequentiallyConsistent).oldValue
    }

    /// The integer's memory, seen as the atomic of the same size and
    /// alignment.
    private static func atomic<Value, Wrapped: ~Copyable>(_ pointer: UnsafeMutablePointer<Value>,
                                                         as type: Wrapped.Type) -> UnsafeMutablePointer<Wrapped> {
        UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: Wrapped.self)
    }
}
