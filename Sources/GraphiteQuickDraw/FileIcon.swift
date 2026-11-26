// The icon a file, folder or bundle has of its own, as Icon Services finds
// it for GetIconRefFromFile: a custom icon kept in the item's resource
// fork, a bundle's CFBundleIconFile, or the .icns file itself. Icons from
// a file's type and creator, and the system's generic ones, are not here.

import GraphiteBase
import GraphiteFiles
import GraphiteResources

extension IconFamily {

    /// kCustomIconResource: where the Finder keeps an item's custom icon.
    public static var customIconResourceID: Int16 { -16455 }

    /// The icon of the item at a path, or nil if it has none (or isn't
    /// there). In the order the Finder looks:
    ///
    /// 1. an .icns file is its own icon;
    /// 2. a custom icon in the item's resource fork: an 'icns' resource, or
    ///    'ICN#', 'icl8' and the rest, all of ID -16455;
    /// 3. a bundle's icon: the file CFBundleIconFile names in its
    ///    Contents/Info.plist, in Contents/Resources;
    /// 4. a folder's custom icon, in the resource fork of its "Icon\r" file.
    ///
    /// The custom icon's Finder flag is not checked: a resource of the ID is
    /// enough.
    public init?(ofItemAt path: String) {
        if path.lowercased().hasSuffix(".icns") {
            guard let family = Self.family(icnsFileAt: path) else { return nil }
            self = family
            return
        }
        if let family = Self.customIcon(inResourceForkOf: path)
            ?? Self.bundleIcon(at: path)
            ?? Self.customIcon(inResourceForkOf: path + "/Icon\r") {
            self = family
            return
        }
        return nil
    }

    private static func family(icnsFileAt path: String) -> IconFamily? {
        guard let fork = try? Fork(path: path, kind: .data, permission: .read),
              let bytes = try? fork.contents() else { return nil }
        return try? IconFamily(icns: bytes)
    }

    private static let customIconTypes: [FourCharCode] = ["ICN#", "ics#", "icl4", "icl8", "ics4", "ics8"]

    private static func customIcon(inResourceForkOf path: String) -> IconFamily? {
        guard let fork = try? Fork(path: path, kind: .resource, permission: .read),
              let resources = try? ResourceFile(fork: fork) else { return nil }
        let id = customIconResourceID
        if let bytes = try? resources.bytes(type: "icns", id: id), let family = try? IconFamily(icns: bytes) {
            return family
        }
        var members: [FourCharCode: [UInt8]] = [:]
        for type in customIconTypes {
            if let bytes = try? resources.bytes(type: type, id: id) { members[type] = bytes }
        }
        return members.isEmpty ? nil : IconFamily(members: members)
    }

    private static func bundleIcon(at path: String) -> IconFamily? {
        guard let fork = try? Fork(path: path + "/Contents/Info.plist", kind: .data, permission: .read),
              let bytes = try? fork.contents(),
              let plist = try? InfoPlist(bytes: bytes),
              let name = plist["CFBundleIconFile"], !name.isEmpty, !name.contains("/") else { return nil }
        let file = name.lowercased().hasSuffix(".icns") ? name : name + ".icns"
        return family(icnsFileAt: path + "/Contents/Resources/" + file)
    }
}
