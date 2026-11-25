// The Script Manager's answers for a system with one script, Roman, set up
// for English and the United States: left to right, MacRoman, the system
// font for the system and Geneva for applications.

public enum ScriptManager {

    /// smRoman.
    public static var romanScript: Int16 { 0 }

    /// IntlScript and the system and keyboard scripts: Roman.
    public static var systemScript: Int16 { romanScript }

    /// GetScriptVariable: what a script's selector reads; zero for any
    /// script but Roman and for selectors not listed.
    public static func scriptVariable(script: Int16, selector: ScriptVariable) -> Int {
        guard script == romanScript else { return 0 }
        switch selector {
        case .enabled: return -1
        case .systemFont: return 0
        case .applicationFont: return 1
        case .systemFontSize, .applicationFontSize: return 12
        case .monospacedFontAndSize, .preferredFontAndSize: return 0x0016_000c   // Monaco 12
        case .smallFontSize, .helpFontSize: return 9
        default: return 0                                                        // left to right, English, MacRoman
        }
    }

    /// GetScriptManagerVariable: the Script Manager's own settings.
    public static func managerVariable(_ selector: ScriptManagerVariable) -> Int {
        switch selector {
        case .version: return 0x0710
        case .enabled: return 1
        default: return 0                                                        // smRoman, verUS
        }
    }
}

/// A script's selector for GetScriptVariable and SetScriptVariable.
public struct ScriptVariable: RawRepresentable, Hashable, Sendable {

    public var rawValue: Int16

    public init(rawValue: Int16) {
        self.rawValue = rawValue
    }

    /// smScriptEnabled.
    public static var enabled: ScriptVariable { ScriptVariable(rawValue: 4) }
    /// smScriptRight: whether the script runs right to left.
    public static var rightToLeft: ScriptVariable { ScriptVariable(rawValue: 6) }
    /// smScriptSysFond.
    public static var systemFont: ScriptVariable { ScriptVariable(rawValue: 12) }
    /// smScriptAppFond.
    public static var applicationFont: ScriptVariable { ScriptVariable(rawValue: 14) }
    /// smScriptNumber: the 'itl0' resource's ID.
    public static var numberResource: ScriptVariable { ScriptVariable(rawValue: 16) }
    /// smScriptDate: the 'itl1' resource's ID.
    public static var dateResource: ScriptVariable { ScriptVariable(rawValue: 18) }
    /// smScriptEncoding.
    public static var encoding: ScriptVariable { ScriptVariable(rawValue: 26) }
    /// smScriptLang.
    public static var language: ScriptVariable { ScriptVariable(rawValue: 28) }
    /// smScriptMonoFondSize: the font in the high word, the size in the low.
    public static var monospacedFontAndSize: ScriptVariable { ScriptVariable(rawValue: 78) }
    /// smScriptPrefFondSize.
    public static var preferredFontAndSize: ScriptVariable { ScriptVariable(rawValue: 80) }
    /// smScriptSmallFondSize.
    public static var smallFontSize: ScriptVariable { ScriptVariable(rawValue: 82) }
    /// smScriptSysFondSize.
    public static var systemFontSize: ScriptVariable { ScriptVariable(rawValue: 84) }
    /// smScriptAppFondSize.
    public static var applicationFontSize: ScriptVariable { ScriptVariable(rawValue: 86) }
    /// smScriptHelpFondSize.
    public static var helpFontSize: ScriptVariable { ScriptVariable(rawValue: 88) }
}

/// A selector for GetScriptManagerVariable.
public struct ScriptManagerVariable: RawRepresentable, Hashable, Sendable {

    public var rawValue: Int16

    public init(rawValue: Int16) {
        self.rawValue = rawValue
    }

    /// smVersion.
    public static var version: ScriptManagerVariable { ScriptManagerVariable(rawValue: 0) }
    /// smEnabled: how many scripts are enabled.
    public static var enabled: ScriptManagerVariable { ScriptManagerVariable(rawValue: 2) }
    /// smSysScript.
    public static var systemScript: ScriptManagerVariable { ScriptManagerVariable(rawValue: 18) }
    /// smKeyScript.
    public static var keyboardScript: ScriptManagerVariable { ScriptManagerVariable(rawValue: 22) }
    /// smRegionCode.
    public static var regionCode: ScriptManagerVariable { ScriptManagerVariable(rawValue: 40) }
    /// smKeyCache.
    public static var keyCache: ScriptManagerVariable { ScriptManagerVariable(rawValue: 64) }
}
