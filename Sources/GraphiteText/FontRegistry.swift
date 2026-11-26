// The Font Manager's families: numbers and names (GetFNum, GetFontName),
// the classic Macintosh fonts' numbers, and the faces registered for them.
// A family with no face of its own is drawn in the closest one there is:
// the classic names map to families a system has, and anything else to the
// built-in face.

import Synchronization
import GraphiteBase

public final class FontRegistry: Sendable {

    /// systemFont, which TextFont(0) means.
    public static var systemFont: Int16 { 0 }

    /// applFont, which TextFont(1) means.
    public static var applicationFont: Int16 { 1 }

    /// The classic fonts' numbers.
    public static let classicFamilies: [Int16: String] = [
        0: "Chicago", 2: "New York", 3: "Geneva", 4: "Monaco", 5: "Venice", 6: "London", 7: "Athens",
        8: "San Francisco", 9: "Toronto", 11: "Cairo", 12: "Los Angeles", 20: "Times", 21: "Helvetica",
        22: "Courier", 23: "Symbol", 24: "Taliesin",
    ]

    /// The families that look most like the classic ones, for faces found
    /// by name on a system that hasn't the classics.
    public static let classicSubstitutes: [String: [String]] = [
        "Chicago": ["Charcoal", "Lucida Grande", "Helvetica", "DejaVu Sans", "Liberation Sans"],
        "Geneva": ["Verdana", "Helvetica", "DejaVu Sans", "Liberation Sans"],
        "New York": ["Times", "Times New Roman", "DejaVu Serif", "Liberation Serif"],
        "Monaco": ["Menlo", "Courier", "DejaVu Sans Mono", "Liberation Mono"],
        "Times": ["Times New Roman", "DejaVu Serif", "Liberation Serif"],
        "Helvetica": ["Arial", "DejaVu Sans", "Liberation Sans"],
        "Courier": ["Courier New", "DejaVu Sans Mono", "Liberation Mono"],
    ]

    private struct State {
        var names: [Int16: String] = FontRegistry.classicFamilies
        var faces: [String: [TextStyle: any FontFace]] = [:]
        var nextNumber: Int16 = 1024
    }

    private let state = Mutex(State())

    /// Finds faces a family hasn't, by name: the host's font lookup.
    public let lookUp: (@Sendable (String) -> (any FontFace)?)?

    public init(lookUp: (@Sendable (String) -> (any FontFace)?)? = nil) {
        self.lookUp = lookUp
    }

    // MARK: Numbers and names

    /// GetFNum: a family's number by its name, in any case; one is given to
    /// a name registered without one.
    public func number(of name: String) -> Int16? {
        state.withLock { state in
            state.names.first { $0.value.lowercased() == name.lowercased() }?.key
        }
    }

    /// GetFontName.
    public func name(of number: Int16) -> String? {
        if number == Self.applicationFont { return state.withLock { $0.names[3] } }
        return state.withLock { $0.names[number] }
    }

    /// Registers a face for a family, under its number, or a new one;
    /// returns the number.
    @discardableResult
    public func register(_ face: any FontFace, style: TextStyle = [], number: Int16? = nil) -> Int16 {
        state.withLock { state in
            let name = face.familyName
            let family = number ?? state.names.first { $0.value.lowercased() == name.lowercased() }?.key ?? {
                defer { state.nextNumber += 1 }
                return state.nextNumber
            }()
            state.names[family] = name
            state.faces[name.lowercased(), default: [:]][style] = face
            return family
        }
    }

    /// The families named, by number.
    public var families: [Int16: String] { state.withLock { $0.names } }

    // MARK: Faces

    /// The face to draw a family in, in a style: its own for the style, else
    /// its plain one; else the host's for its name or a classic
    /// substitute's; else the built-in face.
    public func face(family: Int16, style: TextStyle = []) -> any FontFace {
        let name = self.name(of: family) ?? Self.classicFamilies[0]!
        return face(named: name, style: style)
    }

    public func face(named name: String, style: TextStyle = []) -> any FontFace {
        for candidate in [name] + (Self.classicSubstitutes[name] ?? []) {
            let key = candidate.lowercased()
            if let faces = state.withLock({ $0.faces[key] }), let face = faces[style] ?? faces[[]] { return face }
            if let face = lookUp?(candidate) {
                state.withLock { $0.faces[key, default: [:]][[]] = face }
                return face
            }
        }
        return SystemFont.shared
    }
}
