// A bundle's Info.plist, read as far as Carbon's callers need: the strings
// at the top of its property list (CFBundleIconFile, CFBundleName,
// CFBundleIdentifier). XML and binary lists are both read; nested values and
// numbers are not kept.

import Foundation
import GraphiteBase

public struct InfoPlist: Hashable, Sendable {

    /// The string values of the plist's top-level dictionary, by key.
    public private(set) var strings: [String: String] = [:]

    /// Reads a property list from any bytes, a mapped file's among them. A
    /// parameter error if the bytes are not one; a list whose top level is
    /// not a dictionary reads as empty.
    public init(bytes: some ContiguousBytes) throws(MacError) {
        let data = bytes as? Data ?? bytes.withUnsafeBytes { Data($0) }
        let list: Any
        do {
            list = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw .parameter
        }
        guard let dictionary = list as? [String: Any] else { return }
        for (key, value) in dictionary {
            if let string = value as? String { strings[key] = string }
        }
    }

    public subscript(key: String) -> String? { strings[key] }
}
