import Testing
import GraphiteBase
import GraphiteFiles
import GraphiteAppleEvents

@Suite struct DescriptorTests {

    @Test func nestedListsAndRecords() throws {
        var inner = Descriptor.record([("name", Descriptor(text: "Doc")), ("size", Descriptor(Int32(42)))])
        inner["kind"] = Descriptor(code: "TEXT")
        var list = Descriptor.list([Descriptor(Int16(1)), inner])
        try list.put(Descriptor.list([Descriptor(true)]), at: 0)
        #expect(list.count == 3)
        let record = try list.item(at: 2).descriptor
        #expect(record.isRecord)
        #expect(record["size"]?.load(as: Int32.self) == 42)
        #expect(record["kind"]?.code == "TEXT")
        #expect(try list.item(at: 3).descriptor.items.first?.descriptor == Descriptor(true))
        #expect(throws: MacError.illegalIndex) { try list.item(at: 4) }
        #expect(throws: MacError.illegalIndex) { try list.put(.null, at: 9) }
        // Replacing an item keeps its place.
        try list.put(Descriptor(Int16(7)), at: 1)
        #expect(try list.item(at: 1).descriptor.load(as: Int16.self) == 7)
        try list.removeItem(at: 1)
        #expect(list.count == 2)
        // Values: a copy is its own.
        var copy = list
        copy.items.removeAll()
        #expect(list.count == 2)
    }

    @Test func appleEvents() throws {
        var event = AppleEvent(eventClass: "aevt", eventID: "odoc", target: AppleEvent.currentProcess)
        event[parameter: AppleEvent.Parameter.directObject] = .list()
        #expect(event.eventClass == "aevt")
        #expect(event.eventID == "odoc")
        #expect(event.returnID > 0)
        #expect(event.isForCurrentProcess)
        #expect(event.descriptor.isAppleEvent && !event.descriptor.isRecord)
        #expect(try AppleEvent(event.descriptor) == event)
        #expect(throws: MacError.notAppleEvent) { try AppleEvent(.list()) }
        let other = AppleEvent(eventClass: "aevt", eventID: "quit", target: Descriptor(type: DescriptorType.kernelProcessID, integer: Int32(1)))
        #expect(!other.isForCurrentProcess)
        #expect(AppleEvent(eventClass: "a", eventID: "b", returnID: 5).returnID == 5)
    }

    @Test func printing() {
        let event = AppleEvent(eventClass: "aevt", eventID: "oapp")
        #expect(event.descriptor.description == "'aevt'\\'oapp'{  }")
        #expect(Descriptor.list([Descriptor(Int32(1)), Descriptor(text: "a")]).description == "[1, 'utf8'(\"a\")]")
        #expect(Descriptor.record([("kywd", Descriptor(code: "TEXT"))]).description == "{ kywd:'TEXT' }")
    }
}

@Suite struct CoercionTests {

    let table = CoercionTable()

    @Test func text() throws {
        let utf8 = Descriptor(text: "Café", type: DescriptorType.utf8Text)
        let roman = try table.coerce(utf8, to: DescriptorType.char)
        #expect(roman.bytes == [0x43, 0x61, 0x66, 0x8E])
        let unicode = try table.coerce(roman, to: DescriptorType.unicodeText)
        #expect(Coercion.text(unicode) == "Café")
        // A byte order mark of either order.
        let marked = Descriptor(type: DescriptorType.unicodeText, bytes: withUnsafeBytes(of: UInt16(0xFEFF)) { Array($0) } + unicode.bytes)
        #expect(Coercion.text(marked) == "Café")
        // What MacRoman lacks becomes '?'.
        #expect(try table.coerce(Descriptor(text: "a→b"), to: DescriptorType.char).bytes == Array("a?b".utf8))
    }

    @Test func numbers() throws {
        #expect(try table.coerce(Descriptor(Int16(12)), to: DescriptorType.sInt32).load(as: Int32.self) == 12)
        #expect(try table.coerce(Descriptor(Int32(3)), to: DescriptorType.double).load(as: Double.self) == 3)
        #expect(try table.coerce(Descriptor(text: " 42 "), to: DescriptorType.sInt16).load(as: Int16.self) == 42)
        #expect(Coercion.text(try table.coerce(Descriptor(Int32(-7)), to: DescriptorType.utf8Text)) == "-7")
        #expect(Coercion.text(try table.coerce(Descriptor(2.5), to: DescriptorType.utf8Text)) == "2.5")
        // A value that doesn't fit, or isn't whole, fails.
        #expect(throws: MacError.coercionFailed) { try table.coerce(Descriptor(Int32(70000)), to: DescriptorType.sInt16) }
        #expect(throws: MacError.coercionFailed) { try table.coerce(Descriptor(1.5), to: DescriptorType.sInt32) }
        #expect(throws: MacError.coercionFailed) { try table.coerce(Descriptor(text: "x"), to: DescriptorType.sInt32) }
    }

    @Test func booleans() throws {
        #expect(try table.coerce(Descriptor(Int32(1)), to: DescriptorType.boolean).bytes == [1])
        #expect(try table.coerce(Descriptor(true), to: DescriptorType.true).type == DescriptorType.true)
        #expect(throws: MacError.coercionFailed) { try table.coerce(Descriptor(false), to: DescriptorType.true) }
        #expect(try table.coerce(Descriptor(type: DescriptorType.false), to: DescriptorType.sInt16).load(as: Int16.self) == 0)
    }

    @Test func codesListsAndRecords() throws {
        let code = Descriptor(code: "pnam", type: DescriptorType.property)
        #expect(try table.coerce(code, to: DescriptorType.type).code == "pnam")
        #expect(Coercion.text(try table.coerce(code, to: DescriptorType.utf8Text)) == "pnam")
        #expect(try table.coerce(Descriptor(text: "TEXT"), to: DescriptorType.type).code == "TEXT")
        let list = try table.coerce(Descriptor(Int32(1)), to: DescriptorType.list)
        #expect(list.items.map(\.descriptor) == [Descriptor(Int32(1))])
        // A record as an object specifier stays keyed.
        let specifier = try table.coerce(Descriptor.record([("want", Descriptor(code: "cwin"))]), to: DescriptorType.objectSpecifier)
        #expect(specifier.isKeyed && specifier["want"]?.code == "cwin")
        #expect(throws: MacError.coercionFailed) { try table.coerce(.record(), to: DescriptorType.list) }
        #expect(try table.coerce(Descriptor(Int32(5)), to: DescriptorType.wildCard) == Descriptor(Int32(5)))
    }

    @Test func installedHandlers() throws {
        let table = CoercionTable()
        table.install(from: "QDpt", to: DescriptorType.utf8Text) { descriptor, type in
            Descriptor(text: "point \(descriptor.bytes.count)", type: type)
        }
        #expect(Coercion.text(try table.coerce(Descriptor(type: "QDpt", bytes: [0, 0, 0, 0]), to: DescriptorType.utf8Text)) == "point 4")
        table.install(from: DescriptorType.wildCard, to: "fail") { _, _ throws(MacError) in throw .corruptData }
        #expect(throws: MacError.corruptData) { try table.coerce(Descriptor(Int32(1)), to: "fail") }
        try table.remove(from: "QDpt", to: DescriptorType.utf8Text)
        #expect(throws: MacError.handlerNotFound) { try table.remove(from: "QDpt", to: DescriptorType.utf8Text) }
    }

    @Test func files() throws {
        let folder = TemporaryFolder()
        folder.write("Doc é", [])
        let files = FileSystem(defaultFolder: folder.path)
        let table = CoercionTable(fileCodings: [FileURLCoding(), FileSpecCoding(fileSystem: files), AliasCoding(fileSystem: files)])
        let url = try #require(FileURLCoding().descriptor(forPath: folder.path("Doc é")))
        #expect(String(decoding: url.bytes, as: UTF8.self).hasSuffix("/Doc%20%C3%A9"))
        let spec = try table.coerce(url, to: DescriptorType.fsSpec)
        #expect(spec.bytes.count == 70)
        let alias = try table.coerce(spec, to: DescriptorType.alias)
        let back = try table.coerce(alias, to: DescriptorType.fileURL)
        #expect(FileURLCoding().path(of: back) == folder.path("Doc é"))
        #expect(FileURLCoding().path(of: Descriptor(type: DescriptorType.fileURL, bytes: Array("file://localhost/tmp/a%2Fb".utf8))) == "/tmp/a/b")
        #expect(throws: MacError.coercionFailed) { try table.coerce(Descriptor(type: DescriptorType.fileURL, bytes: Array("http://x".utf8)), to: DescriptorType.fsSpec) }
    }
}
