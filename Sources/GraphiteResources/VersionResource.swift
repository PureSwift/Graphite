// 'vers' resources (Inside Macintosh: Macintosh Toolbox Essentials, 7-70): a
// NumVersion, a region code, and short and long version strings. ID 1 is the
// file's version, 2 the package's it belongs to.

import GraphiteBase

public struct VersionResource: Hashable, Sendable {

    public static var resourceType: FourCharCode { "vers" }

    /// The release stage: development, alpha, beta or final.
    public struct Stage: RawRepresentable, Hashable, Sendable {
        public var rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static var development: Stage { Stage(rawValue: 0x20) }
        public static var alpha: Stage { Stage(rawValue: 0x40) }
        public static var beta: Stage { Stage(rawValue: 0x60) }
        public static var final: Stage { Stage(rawValue: 0x80) }
    }

    /// Binary-coded decimal, as NumVersion keeps it: 0x01 for 1, 0x10 for 10.
    public var major: UInt8

    /// The minor version in the high nibble, the bug-fix in the low.
    public var minorAndBugFix: UInt8

    public var stage: Stage

    /// The prerelease number, 0 for a final release.
    public var nonRelease: UInt8

    /// The Script Manager's region code: 0 for the United States.
    public var region: Int16

    /// "1.0.2", shown in the Finder's list.
    public var shortVersion: PascalString

    /// "1.0.2, © 1997 Someone", shown in Get Info.
    public var longVersion: PascalString

    public init(major: UInt8, minorAndBugFix: UInt8, stage: Stage = .final, nonRelease: UInt8 = 0, region: Int16 = 0,
                shortVersion: PascalString, longVersion: PascalString) {
        self.major = major
        self.minorAndBugFix = minorAndBugFix
        self.stage = stage
        self.nonRelease = nonRelease
        self.region = region
        self.shortVersion = shortVersion
        self.longVersion = longVersion
    }

    /// mapReadErr if the bytes end early.
    public init(bytes: [UInt8]) throws(MacError) {
        var reader = BigEndianReader(bytes)
        do {
            major = try reader.read(UInt8.self)
            minorAndBugFix = try reader.read(UInt8.self)
            stage = Stage(rawValue: try reader.read(UInt8.self))
            nonRelease = try reader.read(UInt8.self)
            region = Int16(bitPattern: try reader.read(UInt16.self))
            shortVersion = PascalString(bytes: try reader.readBytes(Int(try reader.read(UInt8.self))))
            longVersion = PascalString(bytes: try reader.readBytes(Int(try reader.read(UInt8.self))))
        } catch {
            throw .mapRead
        }
    }

    public var bytes: [UInt8] {
        var writer = BigEndianWriter()
        writer.write(major)
        writer.write(minorAndBugFix)
        writer.write(stage.rawValue)
        writer.write(nonRelease)
        writer.write(UInt16(bitPattern: region))
        writer.write(bytes: shortVersion.lengthPrefixed)
        writer.write(bytes: longVersion.lengthPrefixed)
        return writer.bytes
    }

    /// NumVersion's four bytes as one word, as Gestalt and `CFBundle`
    /// report it.
    public var numVersion: UInt32 {
        UInt32(major) << 24 | UInt32(minorAndBugFix) << 16 | UInt32(stage.rawValue) << 8 | UInt32(nonRelease)
    }
}
