// A bundle's Info.plist, read as far as Carbon's callers need: the strings
// at the top of its XML property list (CFBundleIconFile, CFBundleName,
// CFBundleIdentifier). Nested values, numbers and binary property lists are
// not read.

import GraphiteBase

public struct InfoPlist: Hashable, Sendable {

    /// The string values of the plist's top-level dictionary, by key.
    public private(set) var strings: [String: String] = [:]

    /// Reads an XML property list. A binary one ("bplist00") is a
    /// parameter error; text that has no top-level dictionary reads as
    /// empty.
    public init(bytes: [UInt8]) throws(MacError) {
        guard !bytes.starts(with: Array("bplist".utf8)) else { throw .parameter }
        var containers: [String] = []
        var key: String?
        var leaf: String?
        var text = ""
        for event in Self.events(in: bytes) {
            switch event {
            case let .open(name, selfClosing):
                let isTop = containers == ["dict"]
                if name == "dict" || name == "array" {
                    if isTop { key = nil }
                    if !selfClosing { containers.append(name) }
                } else if isTop, name == "key", !selfClosing {
                    leaf = "key"
                    text = ""
                } else if isTop, name == "string" {
                    if selfClosing {
                        if let key { strings[key] = "" }
                        key = nil
                    } else {
                        leaf = "string"
                        text = ""
                    }
                } else if isTop, name != "plist" {
                    // A number, date, boolean or data value: not read.
                    key = nil
                }
            case let .text(string):
                if leaf != nil { text += string }
            case let .close(name):
                if name == leaf {
                    if name == "key" {
                        key = text
                    } else {
                        if let key { strings[key] = text }
                        key = nil
                    }
                    leaf = nil
                } else if name == containers.last {
                    containers.removeLast()
                }
            }
        }
    }

    public subscript(key: String) -> String? { strings[key] }

    // MARK: Tokens

    private enum Event {
        case open(String, selfClosing: Bool)
        case close(String)
        case text(String)
    }

    /// The tags and text of an XML document. Comments, processing
    /// instructions and the DOCTYPE are skipped.
    private static func events(in bytes: [UInt8]) -> [Event] {
        var events: [Event] = []
        var index = 0
        func find(_ marker: String, from start: Int) -> Int? {
            let marker = Array(marker.utf8)
            guard bytes.count >= marker.count, start <= bytes.count - marker.count else { return nil }
            return (start ... bytes.count - marker.count).first { bytes[$0 ..< $0 + marker.count].elementsEqual(marker) }
        }
        func has(_ prefix: String) -> Bool {
            bytes[index...].starts(with: Array(prefix.utf8))
        }
        while index < bytes.count {
            if bytes[index] != UInt8(ascii: "<") {
                let end = bytes[index...].firstIndex(of: UInt8(ascii: "<")) ?? bytes.count
                events.append(.text(decode(bytes[index ..< end])))
                index = end
            } else if has("<!--") {
                index = (find("-->", from: index + 4) ?? bytes.count - 3) + 3
            } else if has("<?") {
                index = (find("?>", from: index + 2) ?? bytes.count - 2) + 2
            } else if has("<![CDATA[") {
                let end = find("]]>", from: index + 9) ?? bytes.count
                events.append(.text(String(decoding: bytes[index + 9 ..< end], as: UTF8.self)))
                index = end + 3
            } else if has("<!") {
                index = (bytes[index...].firstIndex(of: UInt8(ascii: ">")) ?? bytes.count) + 1
            } else {
                guard let end = bytes[index...].firstIndex(of: UInt8(ascii: ">")) else { break }
                var inside = bytes[index + 1 ..< end]
                if inside.first == UInt8(ascii: "/") {
                    events.append(.close(name(of: inside.dropFirst())))
                } else {
                    let selfClosing = inside.last == UInt8(ascii: "/")
                    if selfClosing { inside = inside.dropLast() }
                    events.append(.open(name(of: inside), selfClosing: selfClosing))
                }
                index = end + 1
            }
        }
        return events
    }

    private static func name(of tag: ArraySlice<UInt8>) -> String {
        let end = tag.firstIndex { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") || $0 == UInt8(ascii: "\n") || $0 == UInt8(ascii: "\r") } ?? tag.endIndex
        return String(decoding: tag[tag.startIndex ..< end], as: UTF8.self)
    }

    /// Text with its character references and the five named entities
    /// replaced.
    private static func decode(_ bytes: ArraySlice<UInt8>) -> String {
        let text = String(decoding: bytes, as: UTF8.self)
        guard text.contains("&") else { return text }
        var result = ""
        var rest = Substring(text)
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[rest.startIndex ..< ampersand]
            let after = rest.index(after: ampersand)
            guard let semicolon = rest[after...].firstIndex(of: ";"), rest.distance(from: after, to: semicolon) <= 8 else {
                result.append("&")
                rest = rest[after...]
                continue
            }
            let entity = rest[after ..< semicolon]
            let replacement: Character?
            switch entity {
            case "amp": replacement = "&"
            case "lt": replacement = "<"
            case "gt": replacement = ">"
            case "quot": replacement = "\""
            case "apos": replacement = "'"
            default:
                let number = entity.hasPrefix("#x") ? UInt32(entity.dropFirst(2), radix: 16)
                    : entity.hasPrefix("#") ? UInt32(entity.dropFirst()) : nil
                replacement = number.flatMap(Unicode.Scalar.init).map(Character.init)
            }
            if let replacement {
                result.append(replacement)
                rest = rest[rest.index(after: semicolon)...]
            } else {
                result.append("&")
                rest = rest[after...]
            }
        }
        return result + rest
    }
}
