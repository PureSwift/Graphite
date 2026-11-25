// Multiprocessing Services' memory: blocks at an alignment a program asks
// for, from the C library.

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

public enum MPMemory {

    /// MPAllocateAligned: `size` bytes at a multiple of 2^`alignmentLog2`
    /// bytes, at least 16; zeroed if `clear` (kMPAllocateClearMask). Nil
    /// when there's no memory.
    public static func allocate(size: Int, alignmentLog2: UInt8, clear: Bool = false) -> UnsafeMutableRawPointer? {
        let alignment = 1 << Int(min(max(alignmentLog2, 4), 20))
        var block: UnsafeMutableRawPointer?
        guard posix_memalign(&block, alignment, max(size, 1)) == 0, let block else { return nil }
        if clear { block.initializeMemory(as: UInt8.self, repeating: 0, count: max(size, 0)) }
        return block
    }

    /// MPFree.
    public static func free(_ block: UnsafeMutableRawPointer?) {
        #if canImport(Glibc)
        Glibc.free(block)
        #elseif canImport(Musl)
        Musl.free(block)
        #elseif canImport(Darwin)
        Darwin.free(block)
        #endif
    }
}
