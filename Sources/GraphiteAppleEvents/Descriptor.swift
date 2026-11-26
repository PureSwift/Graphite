// Apple Event descriptors: a type and its data. A list's data is its items;
// a record's its items, each by keyword; an Apple event's its parameters,
// by keyword, and its attributes. Numbers and text in a descriptor's bytes
// are in the program's own byte order, as the Apple Event Manager kept
// them.

import GraphiteBase

public struct Descriptor: Hashable, Sendable {

    /// A list's, record's or event's item: a descriptor and, in a record or
    /// event, its keyword.
    public struct Item: Hashable, Sendable {

        public var keyword: FourCharCode

        public var descriptor: Descriptor

        public init(keyword: FourCharCode = FourCharCode(0), descriptor: Descriptor) {
            self.keyword = keyword
            self.descriptor = descriptor
        }
    }

    public var type: FourCharCode

    /// The data of a descriptor that isn't a list, record or event.
    public var bytes: [UInt8]

    /// A list's items, in order; a record's or event's parameters.
    public var items: [Item]

    /// An Apple event's attributes.
    public var attributes: [Item]

    /// A record, or an event, whose items are found by keyword. A record
    /// coerced to another type, as an object specifier is, stays keyed.
    public var isKeyed: Bool

    public init(type: FourCharCode, bytes: [UInt8] = [], items: [Item] = [], attributes: [Item] = [], isKeyed: Bool = false) {
        self.type = type
        self.bytes = bytes
        self.items = items
        self.attributes = attributes
        self.isKeyed = isKeyed
    }

    /// typeNull, with no data.
    public static var null: Descriptor { Descriptor(type: DescriptorType.null) }

    /// AECreateList: an empty list, or record.
    public static func list(_ items: [Descriptor] = []) -> Descriptor {
        Descriptor(type: DescriptorType.list, items: items.map { Item(descriptor: $0) })
    }

    public static func record(_ items: [(FourCharCode, Descriptor)] = []) -> Descriptor {
        Descriptor(type: DescriptorType.record, items: items.map { Item(keyword: $0.0, descriptor: $0.1) }, isKeyed: true)
    }

    public var isNull: Bool { type == DescriptorType.null }

    public var isList: Bool { type == DescriptorType.list }

    /// AECheckIsRecord: keyed, and not an Apple event.
    public var isRecord: Bool { isKeyed && type != DescriptorType.appleEvent }

    public var isAppleEvent: Bool { type == DescriptorType.appleEvent }

    // MARK: Lists

    /// AECountItems.
    public var count: Int { items.count }

    /// AEGetNthDesc's item: from 1; errAEIllegalIndex past the end.
    public func item(at index: Int) throws(MacError) -> Item {
        guard index >= 1, index <= items.count else { throw .illegalIndex }
        return items[index - 1]
    }

    /// AEPutDesc and AEPutPtr: replaces the index-th item (from 1), keeping
    /// its keyword, or adds one at the end for 0 or one past the last.
    public mutating func put(_ descriptor: Descriptor, at index: Int) throws(MacError) {
        if index >= 1, index <= items.count {
            items[index - 1].descriptor = descriptor
        } else if index == 0 || index == items.count + 1 {
            items.append(Item(descriptor: descriptor))
        } else {
            throw .illegalIndex
        }
    }

    /// AEDeleteItem.
    public mutating func removeItem(at index: Int) throws(MacError) {
        guard index >= 1, index <= items.count else { throw .illegalIndex }
        items.remove(at: index - 1)
    }

    // MARK: Records and events

    /// A record's or event's item of a keyword.
    public subscript(keyword: FourCharCode) -> Descriptor? {
        get { items.first { $0.keyword == keyword }?.descriptor }
        set {
            guard let newValue else {
                items.removeAll { $0.keyword == keyword }
                return
            }
            if let index = items.firstIndex(where: { $0.keyword == keyword }) {
                items[index].descriptor = newValue
            } else {
                items.append(Item(keyword: keyword, descriptor: newValue))
            }
        }
    }

    /// An event's attribute of a keyword.
    public func attribute(_ keyword: FourCharCode) -> Descriptor? {
        attributes.first { $0.keyword == keyword }?.descriptor
    }

    /// Sets an event's attribute, after the others.
    public mutating func setAttribute(_ keyword: FourCharCode, _ descriptor: Descriptor?) {
        attributes.removeAll { $0.keyword == keyword }
        if let descriptor { attributes.append(Item(keyword: keyword, descriptor: descriptor)) }
    }
}

// MARK: - Values

public extension Descriptor {

    /// A value's bytes, in this machine's byte order.
    init<T: FixedWidthInteger>(type: FourCharCode, integer: T) {
        self.init(type: type, bytes: withUnsafeBytes(of: integer) { Array($0) })
    }

    init(_ value: Int16) { self.init(type: DescriptorType.sInt16, integer: value) }

    init(_ value: Int32) { self.init(type: DescriptorType.sInt32, integer: value) }

    init(_ value: Int64) { self.init(type: DescriptorType.sInt64, integer: value) }

    init(_ value: UInt32) { self.init(type: DescriptorType.uInt32, integer: value) }

    init(_ value: Double) { self.init(type: DescriptorType.double, bytes: withUnsafeBytes(of: value) { Array($0) }) }

    init(_ value: Float) { self.init(type: DescriptorType.float, bytes: withUnsafeBytes(of: value) { Array($0) }) }

    init(_ value: Bool) { self.init(type: DescriptorType.boolean, bytes: [value ? 1 : 0]) }

    /// A four-character code as typeType, or typeEnumerated, typeKeyword…
    init(code: FourCharCode, type: FourCharCode = DescriptorType.type) {
        self.init(type: type, integer: code.rawValue)
    }

    /// Text as typeUTF8Text, typeUnicodeText (UTF-16 in this machine's byte
    /// order) or typeChar (MacRoman, '?' for what it lacks).
    init(text: String, type: FourCharCode = DescriptorType.utf8Text) {
        self.init(type: type, bytes: Coercion.textBytes(text, as: type) ?? Array(text.utf8))
    }

    /// The bytes as a value of a type, if there are as many as it has.
    func load<T>(as type: T.Type) -> T? {
        guard bytes.count == MemoryLayout<T>.size else { return nil }
        return bytes.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
    }

    /// A four-character code's descriptor's code.
    var code: FourCharCode? { load(as: UInt32.self).map { FourCharCode(rawValue: $0) } }
}

// MARK: - Printing

extension Descriptor: CustomStringConvertible {

    /// As AEPrintDescToHandle shows it: 'aevt'\'oapp'{ … }, [1, 2],
    /// { kywd:'TEXT'("text") }.
    public var description: String {
        func code(_ value: FourCharCode) -> String { "'\(value.string)'" }
        func list(_ items: [Item], keyed: Bool) -> String {
            items.map { keyed ? "\($0.keyword.string):\($0.descriptor)" : "\($0.descriptor)" }.joined(separator: ", ")
        }
        if isAppleEvent {
            let eventClass = attribute(AppleEvent.Attribute.eventClass)?.code ?? FourCharCode(0)
            let eventID = attribute(AppleEvent.Attribute.eventID)?.code ?? FourCharCode(0)
            return "\(code(eventClass))\\\(code(eventID)){ \(list(items, keyed: true)) }"
        }
        if isList { return "[\(list(items, keyed: false))]" }
        if isKeyed { return (type == DescriptorType.record ? "" : code(type)) + "{ \(list(items, keyed: true)) }" }
        if let text = Coercion.text(self) { return "\(code(type))(\"\(text)\")" }
        if Coercion.numericTypes.contains(type), let value = Coercion.double(self) {
            return value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(value)
        }
        if Coercion.codeTypes.contains(type), let value = self.code { return code(value) }
        let hex = bytes.map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
        return "\(code(type))(\(hex))"
    }
}

/// Descriptor types.
public enum DescriptorType {
    public static var null: FourCharCode { "null" }
    public static var wildCard: FourCharCode { "****" }
    public static var list: FourCharCode { "list" }
    public static var record: FourCharCode { "reco" }
    public static var appleEvent: FourCharCode { "aevt" }
    public static var type: FourCharCode { "type" }
    public static var enumerated: FourCharCode { "enum" }
    public static var keyword: FourCharCode { "keyw" }
    public static var property: FourCharCode { "prop" }
    public static var boolean: FourCharCode { "bool" }
    public static var `true`: FourCharCode { "true" }
    public static var `false`: FourCharCode { "fals" }
    public static var sInt16: FourCharCode { "shor" }
    public static var sInt32: FourCharCode { "long" }
    public static var sInt64: FourCharCode { "comp" }
    public static var uInt32: FourCharCode { "magn" }
    public static var float: FourCharCode { "sing" }
    public static var double: FourCharCode { "doub" }
    public static var char: FourCharCode { "TEXT" }
    public static var utf8Text: FourCharCode { "utf8" }
    public static var unicodeText: FourCharCode { "utxt" }
    public static var processSerialNumber: FourCharCode { "psn " }
    public static var kernelProcessID: FourCharCode { "kpid" }
    public static var applicationBundleID: FourCharCode { "bund" }
    public static var fileURL: FourCharCode { "furl" }
    public static var fsSpec: FourCharCode { "fss " }
    public static var fsRef: FourCharCode { "fsrf" }
    public static var alias: FourCharCode { "alis" }
    public static var objectSpecifier: FourCharCode { "obj " }
}
