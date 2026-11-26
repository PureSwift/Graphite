// FindFolder: the special folders a program asks for by type. A Linux
// program gets the XDG base and user directories; a Mac program can be
// given the folders its Foundation's search paths give, in the home's
// Library.

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import GraphiteBase

/// FindFolder's folder types.
public enum FolderType {
    public static var preferences: GraphiteBase.FourCharCode { "pref" }
    public static var applicationSupport: GraphiteBase.FourCharCode { "asup" }
    public static var caches: GraphiteBase.FourCharCode { "cach" }
    public static var domainLibrary: GraphiteBase.FourCharCode { "dlib" }
    public static var documents: GraphiteBase.FourCharCode { "docs" }
    public static var desktop: GraphiteBase.FourCharCode { "desk" }
    public static var trash: GraphiteBase.FourCharCode { "trsh" }
    public static var applications: GraphiteBase.FourCharCode { "apps" }
    public static var fonts: GraphiteBase.FourCharCode { "font" }
    public static var fontCollections: GraphiteBase.FourCharCode { "fnts" }
    public static var frameworks: GraphiteBase.FourCharCode { "fram" }
    public static var logs: GraphiteBase.FourCharCode { "logs" }
    public static var systemSounds: GraphiteBase.FourCharCode { "ssnd" }
    public static var currentUser: GraphiteBase.FourCharCode { "cusr" }
    public static var temporary: GraphiteBase.FourCharCode { "temp" }
    public static var chewableItems: GraphiteBase.FourCharCode { "chew" }
    public static var music: GraphiteBase.FourCharCode { "µdoc" }
    public static var pictures: GraphiteBase.FourCharCode { "pdoc" }
    public static var movies: GraphiteBase.FourCharCode { "mdoc" }
    public static var downloads: GraphiteBase.FourCharCode { "down" }
}

/// Where each special folder is.
public struct FolderLocations: Sendable {

    /// A folder type's path, or nil for one there is none of.
    public var path: @Sendable (GraphiteBase.FourCharCode) -> String?

    public init(path: @escaping @Sendable (GraphiteBase.FourCharCode) -> String?) {
        self.path = path
    }

    /// The XDG base directories and user directories (user-dirs.dirs), with
    /// their defaults where they aren't set.
    public static var xdg: FolderLocations {
        FolderLocations { type in
            let home = POSIX.environment("HOME") ?? "/"
            func base(_ variable: String, _ fallback: String) -> String {
                POSIX.environment(variable).flatMap { $0.hasPrefix("/") ? $0 : nil } ?? home + "/" + fallback
            }
            let data = base("XDG_DATA_HOME", ".local/share")
            let config = base("XDG_CONFIG_HOME", ".config")
            switch type {
            case FolderType.preferences: return config
            case FolderType.applicationSupport, FolderType.domainLibrary: return data
            case FolderType.caches: return base("XDG_CACHE_HOME", ".cache")
            case FolderType.logs: return base("XDG_STATE_HOME", ".local/state")
            case FolderType.documents: return userDirectory("DOCUMENTS", config: config, home: home) ?? home + "/Documents"
            case FolderType.desktop: return userDirectory("DESKTOP", config: config, home: home) ?? home + "/Desktop"
            case FolderType.music: return userDirectory("MUSIC", config: config, home: home) ?? home + "/Music"
            case FolderType.pictures: return userDirectory("PICTURES", config: config, home: home) ?? home + "/Pictures"
            case FolderType.movies: return userDirectory("VIDEOS", config: config, home: home) ?? home + "/Videos"
            case FolderType.downloads: return userDirectory("DOWNLOAD", config: config, home: home) ?? home + "/Downloads"
            case FolderType.trash: return data + "/Trash/files"
            case FolderType.applications: return data + "/applications"
            case FolderType.fonts, FolderType.fontCollections: return data + "/fonts"
            case FolderType.systemSounds: return data + "/sounds"
            case FolderType.currentUser: return home
            case FolderType.temporary, FolderType.chewableItems: return POSIX.environment("TMPDIR") ?? "/tmp"
            default: return nil
            }
        }
    }

    /// As a Mac's home has them, in `home`'s Library, which is where
    /// Foundation's search paths put them.
    public static func macHome(_ home: String) -> FolderLocations {
        FolderLocations { type in
            switch type {
            case FolderType.preferences: return home + "/Library/Preferences"
            case FolderType.applicationSupport: return home + "/Library/Application Support"
            case FolderType.caches: return home + "/Library/Caches"
            case FolderType.domainLibrary: return home + "/Library"
            case FolderType.documents: return home + "/Documents"
            case FolderType.desktop: return home + "/Desktop"
            case FolderType.music: return home + "/Music"
            case FolderType.pictures: return home + "/Pictures"
            case FolderType.movies: return home + "/Movies"
            case FolderType.downloads: return home + "/Downloads"
            case FolderType.trash: return home + "/.Trash"
            case FolderType.applications: return home + "/Applications"
            case FolderType.fonts, FolderType.fontCollections: return home + "/Library/Fonts"
            case FolderType.frameworks: return home + "/Library/Frameworks"
            case FolderType.logs: return home + "/Library/Logs"
            case FolderType.systemSounds: return home + "/Library/Sounds"
            case FolderType.currentUser: return home
            case FolderType.temporary, FolderType.chewableItems: return POSIX.environment("TMPDIR") ?? "/tmp"
            default: return nil
            }
        }
    }

    /// XDG_<name>_DIR from user-dirs.dirs: "$HOME/Documents" or an absolute
    /// path, in quotes.
    static func userDirectory(_ name: String, config: String, home: String) -> String? {
        guard let bytes = POSIX.readFile(config + "/user-dirs.dirs") else { return nil }
        let key = "XDG_\(name)_DIR="
        for line in String(decoding: bytes, as: UTF8.self).split(separator: "\n") {
            let line = line.drop { $0 == " " || $0 == "\t" }
            guard line.hasPrefix(key) else { continue }
            var value = String(line.dropFirst(key.count))
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { value = String(value.dropFirst().dropLast()) }
            if value.hasPrefix("$HOME") { value = home + value.dropFirst(5) }
            return value.hasPrefix("/") ? value : nil
        }
        return nil
    }
}

public extension FileSystem {

    /// FindFolder: a special folder's path, made first if it isn't there
    /// and `create` asks for it.
    func findFolder(_ type: GraphiteBase.FourCharCode, create: Bool) throws(MacError) -> String {
        guard let path = state.withLock({ $0.folders }).path(type) else { throw .fileNotFound }
        if ItemStatus(path: path)?.isDirectory != true {
            guard create else { throw .fileNotFound }
            guard POSIX.makeFolders(path) else { throw .directoryNotFound }
        }
        return path
    }

    /// Where the special folders are, from now on.
    var folderLocations: FolderLocations {
        get { state.withLock { $0.folders } }
        set { state.withLock { $0.folders = newValue } }
    }
}
