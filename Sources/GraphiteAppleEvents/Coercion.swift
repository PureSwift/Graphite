// Coercion: a descriptor as another type, as AECoerceDesc and the Get calls
// with a desired type give it. The Apple Event Manager's own coercions are
// between text types, numbers, booleans, four-character codes, lists and
// records, and between file types; a program installs more with
// AEInstallCoercionHandler.

import Synchronization
import GraphiteBase
import GraphiteFiles

/// The standard coercions, which need no table.
public enum Coercion {

    static let textTypes: Set<FourCharCode> = [DescriptorType.char, DescriptorType.utf8Text, DescriptorType.unicodeText]

    static let codeTypes: Set<FourCharCode> = [DescriptorType.type, DescriptorType.enumerated, DescriptorType.keyword, DescriptorType.property]

    static let numericTypes: Set<FourCharCode> = [
        DescriptorType.sInt16, DescriptorType.sInt32, DescriptorType.sInt64, DescriptorType.uInt32, DescriptorType.float,
        DescriptorType.double, DescriptorType.boolean, DescriptorType.true, DescriptorType.false,
    ]

    /// A text descriptor's text.
    public static func text(_ descriptor: Descriptor) -> String? {
        let bytes = descriptor.bytes
        switch descriptor.type {
        case DescriptorType.utf8Text:
            return String(validating: bytes, as: UTF8.self)
        case DescriptorType.unicodeText:
            guard bytes.count % 2 == 0 else { return nil }
            var units = bytes.withUnsafeBytes { raw in
                (0 ..< raw.count / 2).map { raw.loadUnaligned(fromByteOffset: $0 * 2, as: UInt16.self) }
            }
            // After a byte order mark if there is one, of either order.
            if units.first == 0xFEFF {
                units.removeFirst()
            } else if units.first == 0xFFFE {
                units = units.dropFirst().map(\.byteSwapped)
            }
            return String(validating: units, as: UTF16.self)
        case DescriptorType.char:
            return MacRoman.decode(bytes)
        default:
            return nil
        }
    }

    /// Text as a text type's bytes: MacRoman for typeChar, with '?' for what
    /// MacRoman lacks.
    public static func textBytes(_ text: String, as type: FourCharCode) -> [UInt8]? {
        switch type {
        case DescriptorType.utf8Text:
            return Array(text.utf8)
        case DescriptorType.unicodeText:
            return text.utf16.flatMap { unit in withUnsafeBytes(of: unit) { Array($0) } }
        case DescriptorType.char:
            return MacRoman.encode(text) ?? text.map { MacRoman.byte($0) ?? UInt8(ascii: "?") }
        default:
            return nil
        }
    }

    /// A number's value, from a numeric, boolean or text descriptor.
    public static func double(_ descriptor: Descriptor) -> Double? {
        switch descriptor.type {
        case DescriptorType.sInt16: return descriptor.load(as: Int16.self).map(Double.init)
        case DescriptorType.sInt32: return descriptor.load(as: Int32.self).map(Double.init)
        case DescriptorType.sInt64: return descriptor.load(as: Int64.self).map(Double.init)
        case DescriptorType.uInt32: return descriptor.load(as: UInt32.self).map(Double.init)
        case DescriptorType.float: return descriptor.load(as: Float.self).map(Double.init)
        case DescriptorType.double: return descriptor.load(as: Double.self)
        case DescriptorType.boolean: return descriptor.bytes.first.map { $0 == 0 ? 0 : 1 }
        case DescriptorType.true: return 1
        case DescriptorType.false: return 0
        default:
            return text(descriptor).flatMap { Double($0.trimmingSpaces) }
        }
    }

    static func numberBytes(_ value: Double, as type: FourCharCode) -> [UInt8]? {
        func integer<T: FixedWidthInteger>(_: T.Type) -> [UInt8]? {
            guard value.rounded() == value, let exact = T(exactly: value) else { return nil }
            return withUnsafeBytes(of: exact) { Array($0) }
        }
        switch type {
        case DescriptorType.sInt16: return integer(Int16.self)
        case DescriptorType.sInt32: return integer(Int32.self)
        case DescriptorType.sInt64: return integer(Int64.self)
        case DescriptorType.uInt32: return integer(UInt32.self)
        case DescriptorType.float: return withUnsafeBytes(of: Float(value)) { Array($0) }
        case DescriptorType.double: return withUnsafeBytes(of: value) { Array($0) }
        case DescriptorType.boolean: return value == 0 || value == 1 ? [UInt8(value)] : nil
        default: return nil
        }
    }

    /// The standard coercion of a descriptor to a type; nil where there is
    /// none.
    public static func standard(_ descriptor: Descriptor, to type: FourCharCode) -> Descriptor? {
        if type == DescriptorType.wildCard || type == descriptor.type { return descriptor }
        var result = Descriptor(type: type)
        if type == DescriptorType.list {
            guard !descriptor.isKeyed else { return nil }
            result.items = [Descriptor.Item(descriptor: descriptor)]
            return result
        }
        if descriptor.isKeyed {
            // A record as a record of another type, as an object specifier
            // is made.
            guard !descriptor.isAppleEvent, !textTypes.contains(type), !numericTypes.contains(type) else { return nil }
            result.items = descriptor.items
            result.isKeyed = true
            return result
        }
        if codeTypes.contains(type), codeTypes.contains(descriptor.type), descriptor.bytes.count == 4 {
            result.bytes = descriptor.bytes
            return result
        }
        if textTypes.contains(type) {
            if let text = text(descriptor), let bytes = textBytes(text, as: type) {
                result.bytes = bytes
                return result
            }
            if numericTypes.contains(descriptor.type), let value = double(descriptor),
               let bytes = textBytes(value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(value), as: type) {
                result.bytes = bytes
                return result
            }
            if codeTypes.contains(descriptor.type), let code = descriptor.code, let bytes = textBytes(code.string, as: type) {
                result.bytes = bytes
                return result
            }
            return nil
        }
        if codeTypes.contains(type), textTypes.contains(descriptor.type), let text = text(descriptor),
           let code = FourCharCode(text), text.unicodeScalars.count == 4 {
            return Descriptor(code: code, type: type)
        }
        if numericTypes.contains(type), let value = double(descriptor) {
            if type == DescriptorType.true || type == DescriptorType.false {
                return (value != 0) == (type == DescriptorType.true) ? result : nil
            }
            guard let bytes = numberBytes(value, as: type) else { return nil }
            result.bytes = bytes
            return result
        }
        return nil
    }
}

/// How a file descriptor type names a file: its path from the descriptor's
/// bytes, and the bytes for a path.
public protocol FileDescriptorCoding: Sendable {

    var type: FourCharCode { get }

    func path(of descriptor: Descriptor) -> String?

    func descriptor(forPath path: String) -> Descriptor?
}

/// typeFileURL: a "file://" URL's text.
public struct FileURLCoding: FileDescriptorCoding {

    public init() {}

    public var type: FourCharCode { DescriptorType.fileURL }

    public func path(of descriptor: Descriptor) -> String? {
        guard let text = String(validating: descriptor.bytes, as: UTF8.self), text.hasPrefix("file://") else { return nil }
        var rest = Substring(text.dropFirst(7))
        // "file://localhost/path" or "file:///path".
        if let slash = rest.firstIndex(of: "/") { rest = rest[slash...] } else { return nil }
        return Self.percentDecoded(rest)
    }

    public func descriptor(forPath path: String) -> Descriptor? {
        Descriptor(type: type, bytes: Array(("file://" + Self.percentEncoded(path)).utf8))
    }

    static func percentEncoded(_ path: String) -> String {
        var encoded = ""
        for byte in path.utf8 {
            switch byte {
            case UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "A") ... UInt8(ascii: "Z"), UInt8(ascii: "0") ... UInt8(ascii: "9"),
                 UInt8(ascii: "/"), UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "~"):
                encoded.unicodeScalars.append(Unicode.Scalar(byte))
            default:
                let hex = String(byte, radix: 16, uppercase: true)
                encoded += "%" + (hex.count == 1 ? "0" : "") + hex
            }
        }
        return encoded
    }

    static func percentDecoded(_ text: Substring) -> String? {
        var bytes: [UInt8] = []
        var index = text.utf8.startIndex
        let utf8 = text.utf8
        while index < utf8.endIndex {
            let byte = utf8[index]
            if byte == UInt8(ascii: "%") {
                let high = utf8.index(after: index)
                guard high < utf8.endIndex, utf8.index(after: high) < utf8.endIndex else { return nil }
                let low = utf8.index(after: high)
                guard let value = UInt8(String(decoding: [utf8[high], utf8[low]], as: UTF8.self), radix: 16) else { return nil }
                bytes.append(value)
                index = utf8.index(after: low)
            } else {
                bytes.append(byte)
                index = utf8.index(after: index)
            }
        }
        return String(validating: bytes, as: UTF8.self)
    }
}

/// typeFSS: an FSSpec's 70 bytes, packed to two: its volume, its folder's
/// ID and its name as a Str63, numbers in this machine's byte order.
public struct FileSpecCoding: FileDescriptorCoding {

    public let fileSystem: FileSystem

    public init(fileSystem: FileSystem) {
        self.fileSystem = fileSystem
    }

    public var type: FourCharCode { DescriptorType.fsSpec }

    public func path(of descriptor: Descriptor) -> String? {
        let bytes = descriptor.bytes
        guard bytes.count >= 70 else { return nil }
        let (volume, parent) = bytes.withUnsafeBytes {
            ($0.loadUnaligned(as: Int16.self), $0.loadUnaligned(fromByteOffset: 2, as: UInt32.self))
        }
        let spec = FileSpec(volume: volume, parent: DirectoryID(parent), name: PascalString(lengthPrefixed: bytes[6 ..< 70]))
        return fileSystem.path(of: spec)
    }

    public func descriptor(forPath path: String) -> Descriptor? {
        let spec = fileSystem.spec(forPath: path)
        var bytes = withUnsafeBytes(of: spec.volume) { Array($0) } + withUnsafeBytes(of: spec.parent.rawValue) { Array($0) }
        let name = spec.name.lengthPrefixed.prefix(64)
        bytes += name + [UInt8](repeating: 0, count: 64 - name.count)
        return Descriptor(type: type, bytes: bytes)
    }
}

/// typeAlias: an alias record, its user type and size first in this
/// machine's byte order.
public struct AliasCoding: FileDescriptorCoding {

    public let fileSystem: FileSystem?

    public init(fileSystem: FileSystem? = nil) {
        self.fileSystem = fileSystem
    }

    public var type: FourCharCode { DescriptorType.alias }

    public func path(of descriptor: Descriptor) -> String? {
        guard descriptor.bytes.count > 6, let alias = try? Alias(record: descriptor.bytes.dropFirst(6)) else { return nil }
        return try? alias.resolve(in: fileSystem).path
    }

    public func descriptor(forPath path: String) -> Descriptor? {
        guard let alias = try? Alias(target: path) else { return nil }
        let record = alias.record
        guard record.count + 6 <= Int(UInt16.max) else { return nil }
        let header = withUnsafeBytes(of: UInt32(0)) { Array($0) } + withUnsafeBytes(of: UInt16(record.count + 6)) { Array($0) }
        return Descriptor(type: type, bytes: header + record)
    }
}

/// The coercions a program has: its handlers first, then the file types',
/// then the standard ones.
public final class CoercionTable: Sendable {

    /// A coercion handler: the descriptor as the type, or a thrown error.
    public typealias Handler = @Sendable (Descriptor, FourCharCode) throws(MacError) -> Descriptor

    private struct Key: Hashable {
        var from: FourCharCode
        var to: FourCharCode
    }

    private struct State {
        var handlers: [Key: Handler] = [:]
        var files: [FourCharCode: any FileDescriptorCoding] = [:]
    }

    private let state: Mutex<State>

    public init(fileCodings: [any FileDescriptorCoding] = [FileURLCoding()]) {
        var state = State()
        for coding in fileCodings { state.files[coding.type] = coding }
        self.state = Mutex(state)
    }

    /// AEInstallCoercionHandler: from typeWildCard is from any type.
    public func install(from: FourCharCode, to: FourCharCode, handler: @escaping Handler) {
        state.withLock { $0.handlers[Key(from: from, to: to)] = handler }
    }

    /// AERemoveCoercionHandler: errAEHandlerNotFound if none is installed.
    public func remove(from: FourCharCode, to: FourCharCode) throws(MacError) {
        guard state.withLock({ $0.handlers.removeValue(forKey: Key(from: from, to: to)) }) != nil else { throw .handlerNotFound }
    }

    public func handler(from: FourCharCode, to: FourCharCode) -> Handler? {
        state.withLock { $0.handlers[Key(from: from, to: to)] }
    }

    /// Adds or replaces how a file type names files.
    public func add(_ coding: any FileDescriptorCoding) {
        state.withLock { $0.files[coding.type] = coding }
    }

    public var fileTypes: Set<FourCharCode> { state.withLock { Set($0.files.keys) } }

    /// AECoerceDesc: errAECoercionFail where there is no coercion.
    public func coerce(_ descriptor: Descriptor, to type: FourCharCode) throws(MacError) -> Descriptor {
        if type == DescriptorType.wildCard || type == descriptor.type { return descriptor }
        let (handler, files) = state.withLock { state in
            (state.handlers[Key(from: descriptor.type, to: type)] ?? state.handlers[Key(from: DescriptorType.wildCard, to: type)], state.files)
        }
        if let handler { return try handler(descriptor, type) }
        if let source = files[descriptor.type], let target = files[type] {
            guard let path = source.path(of: descriptor), let result = target.descriptor(forPath: path) else { throw .coercionFailed }
            return result
        }
        guard let result = Coercion.standard(descriptor, to: type) else { throw .coercionFailed }
        return result
    }
}

private extension String {
    var trimmingSpaces: String {
        var view = Substring(self)
        while let first = view.first, first == " " || first == "\t" || first == "\r" || first == "\n" { view.removeFirst() }
        while let last = view.last, last == " " || last == "\t" || last == "\r" || last == "\n" { view.removeLast() }
        return String(view)
    }
}
