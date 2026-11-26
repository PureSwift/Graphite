// The one volume, "Macintosh HD" at the root, and the space it has.

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// A volume: its reference number and name, and where its space is
/// counted.
public struct Volume: Hashable, Sendable {

    /// -100, as the startup volume's has been since System 7's File Manager.
    public var reference: Int16

    public var name: String

    /// Where the volume's space is counted: the file system the program
    /// writes to, the home's by default. The root may be another with no
    /// room at all (a read-only system image), and a program that checks
    /// for room before it starts would stop.
    public var spacePath: String

    public init(reference: Int16 = -100, name: String = "Macintosh HD", spacePath: String? = nil) {
        self.reference = reference
        self.name = name
        self.spacePath = spacePath ?? POSIX.environment("HOME") ?? "/"
    }

    /// The volume's size and free space, in bytes.
    public var space: Space? { Space(path: spacePath) }

    public struct Space: Hashable, Sendable {

        public var total: UInt64

        public var free: UInt64

        public init(total: UInt64, free: UInt64) {
            self.total = total
            self.free = free
        }

        /// The space of the file system a path is on.
        public init?(path: String) {
            var stats = statvfs()
            guard statvfs(path, &stats) == 0 else { return nil }
            let block = UInt64(stats.f_frsize)
            total = UInt64(stats.f_blocks) * block
            free = UInt64(stats.f_bavail) * block
        }

        /// As the File Manager reported a volume through 16-bit block
        /// counts (PBHGetVInfo): its sizes at most 2 GB, so that blocks
        /// times their size fits 32 bits, in blocks of 512 bytes or a power
        /// of two larger, as few as fit 16 bits.
        public var classic: (blockSize: UInt32, blocks: UInt16, freeBlocks: UInt16) {
            let limit: UInt64 = 0x7FFF_FFFF
            let total = min(total, limit), free = min(free, limit)
            var size: UInt64 = 512
            while total / size > 0xFFFF { size *= 2 }
            return (UInt32(size), UInt16(total / size), UInt16(free / size))
        }

        /// As FSGetVolumeInfo reports it, in 32-bit block counts.
        public var blocks: (blockSize: UInt32, blocks: UInt32, freeBlocks: UInt32) {
            var size: UInt64 = 4096
            while total / size > UInt64(UInt32.max) { size *= 2 }
            return (UInt32(size), UInt32(total / size), UInt32(free / size))
        }
    }
}
