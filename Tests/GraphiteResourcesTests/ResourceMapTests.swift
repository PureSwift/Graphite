import Testing
import GraphiteBase
import GraphiteResources

@Suite struct ResourceMapTests {

    static let resources: [(resource: Resource, bytes: [UInt8])] = [
        (Resource(type: "STR#", id: 128, name: "Messages"), StringList(strings: ["One", "Two"]).bytes),
        (Resource(type: "PICT", id: 1000), [1, 2, 3, 4]),
        (Resource(type: "STR#", id: 129, attributes: [.purgeable, .protected]), []),
        (Resource(type: "vers", id: 1), [0x01, 0x02, 0x80, 0, 0, 0, 1, 0x31, 1, 0x31]),
    ]

    @Test func mapsWrittenReadBackTheSame() throws {
        let fork = try ResourceMap.write(Self.resources, attributes: .compact)
        let map = try ResourceMap(parsing: fork)
        #expect(map.attributes == .compact)
        // Each type's resources together, the types in the order they came.
        #expect(map.types == ["STR#", "PICT", "vers"])
        #expect(map.entries.map(\.resource.id) == [128, 129, 1000, 1])
        for (resource, bytes) in Self.resources {
            let entry = try #require(map.entries.first { $0.resource.type == resource.type && $0.resource.id == resource.id })
            #expect(entry.resource == resource)
            #expect(Array(fork[entry.data]) == bytes)
        }
        // Written again, the same bytes.
        let again = try ResourceMap.write(map.entries.map { ($0.resource, Array(fork[$0.data])) }, attributes: map.attributes)
        #expect(try ResourceMap(parsing: again).entries.map(\.resource) == map.entries.map(\.resource))
    }

    @Test func theHeaderIsAsTheResourceManagerWritesIt() throws {
        let fork = try ResourceMap.write(Self.resources)
        let reader = BigEndianReader(fork)
        #expect(try reader.peek(UInt32.self, at: 0) == 256)
        let mapOffset = Int(try reader.peek(UInt32.self, at: 4))
        // The map starts with a copy of the header.
        #expect(Array(fork[mapOffset ..< mapOffset + 16]) == Array(fork[0 ..< 16]))
        #expect(try reader.peek(UInt16.self, at: mapOffset + 24) == 28)
    }

    @Test func emptyForks() throws {
        let map = try ResourceMap(parsing: ResourceMap.emptyFork)
        #expect(map.entries.isEmpty)
        #expect(throws: MacError.endOfFile) { try ResourceMap(parsing: []) }
    }

    @Test func reservedHeaderBytesAreKept() throws {
        let reserved = (0 ..< 240).map { UInt8(truncatingIfNeeded: $0) }
        let fork = try ResourceMap.write(Self.resources, reservedHeader: reserved)
        #expect(try ResourceMap(parsing: fork).reservedHeader == reserved)
    }

    @Test func badOffsetsThrow() throws {
        var fork = try ResourceMap.write(Self.resources)
        // The map's offset past the end.
        fork.replaceSubrange(4 ..< 8, with: [0xFF, 0xFF, 0xFF, 0x00])
        #expect(throws: MacError.mapRead) { try ResourceMap(parsing: fork) }
        // A resource's data offset past the data.
        var other = try ResourceMap.write(Self.resources)
        let mapOffset = Int(try BigEndianReader(other).peek(UInt32.self, at: 4))
        let reference = mapOffset + 28 + 2 + 8 * 3 + 5
        other[reference] = 0x7F
        #expect(throws: MacError.mapRead) { try ResourceMap(parsing: other) }
    }

    /// Whatever the bytes, parsing throws or succeeds, and never traps.
    @Test func truncatedAndDamagedForksNeverTrap() throws {
        let fork = try ResourceMap.write(Self.resources)
        for length in 0 ..< fork.count {
            _ = try? ResourceMap(parsing: Array(fork.prefix(length)))
        }
        var random = SystemRandomNumberGenerator()
        for _ in 0 ..< 2000 {
            var damaged = fork
            for _ in 0 ..< Int.random(in: 1 ... 8, using: &random) {
                damaged[Int.random(in: 0 ..< damaged.count, using: &random)] = UInt8.random(in: 0 ... 255, using: &random)
            }
            if let map = try? ResourceMap(parsing: damaged) {
                for entry in map.entries { #expect(entry.data.upperBound <= damaged.count) }
            }
        }
        for _ in 0 ..< 500 {
            let bytes = (0 ..< Int.random(in: 0 ... 600, using: &random)).map { _ in UInt8.random(in: 0 ... 255, using: &random) }
            _ = try? ResourceMap(parsing: bytes)
        }
    }

    @Test func typedResources() throws {
        let list = try StringList(bytes: StringList(strings: ["a", "bc"]).bytes)
        #expect(list.strings == ["a", "bc"])
        #expect(list[2] == "bc")
        #expect(list[3] == PascalString())
        #expect(throws: MacError.mapRead) { try StringList(bytes: [0, 2, 1, 0x61]) }
        #expect(StringResource(bytes: [3, 0x61, 0x62, 0x63]).string == "abc")
        #expect(StringResource(bytes: [9, 0x61]).string == "a")

        let version = VersionResource(major: 0x01, minorAndBugFix: 0x02, stage: .beta, nonRelease: 3, shortVersion: "1.0.2b3",
                                      longVersion: "1.0.2b3, © 1999")
        #expect(try VersionResource(bytes: version.bytes) == version)
        #expect(version.numVersion == 0x0102_6003)
        #expect(throws: MacError.mapRead) { try VersionResource(bytes: [1, 2, 3]) }
    }
}
