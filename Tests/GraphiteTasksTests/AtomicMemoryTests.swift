import Testing
import GraphiteBase
import GraphiteTasks

@Suite struct AtomicMemoryTests {

    @Test func arithmetic() {
        let value = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        defer { value.deallocate() }
        value.initialize(to: 10)
        #expect(AtomicMemory.add(5, to: value) == 15)
        #expect(AtomicMemory.add(-20, to: value) == -5)
        #expect(AtomicMemory.increment(value) == -5)
        #expect(AtomicMemory.decrement(value) == -4)
        #expect(value.pointee == -5)
        value.pointee = .max
        #expect(AtomicMemory.add(1, to: value) == .min)
    }

    @Test func sixteenBits() {
        let value = UnsafeMutablePointer<Int16>.allocate(capacity: 1)
        defer { value.deallocate() }
        value.initialize(to: 100)
        #expect(AtomicMemory.add(Int16(-1), to: value) == 99)
    }

    @Test func compareAndSwapAndBits() {
        let value = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        defer { value.deallocate() }
        value.initialize(to: 1)
        #expect(AtomicMemory.compareAndSwap(1, 2, at: value))
        #expect(!AtomicMemory.compareAndSwap(1, 3, at: value))
        #expect(value.pointee == 2)
        #expect(AtomicMemory.or(0x10, into: value) == 2)
        #expect(AtomicMemory.and(0x10, into: value) == 0x12)
        #expect(AtomicMemory.xor(0x11, into: value) == 0x10)
        #expect(value.pointee == 0x01)
    }
}
