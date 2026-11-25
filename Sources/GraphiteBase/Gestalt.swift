// Gestalt: answers to selectors, which the host fills in. The standard
// table answers what CoreServices' and Carbon's providers answered between
// them: the system's version, its memory and its processor. Libraries
// register their own (QuickTime its version, when it is there).

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// Gestalt's table of selectors and their answers.
public struct Gestalt: Sendable {

    /// An answer: a number, or a function asked each time.
    public enum Answer: Sendable {
        case value(Int32)
        case function(@Sendable (FourCharCode) throws(MacError) -> Int32)
    }

    private var answers: [FourCharCode: Answer]

    /// An empty table.
    public init() {
        self.answers = [:]
    }

    public var selectors: some Collection<FourCharCode> { answers.keys }

    /// Gestalt: the answer for a selector, or gestaltUndefSelectorErr.
    public func response(for selector: FourCharCode) throws(MacError) -> Int32 {
        switch answers[selector] {
        case .value(let value): return value
        case .function(let function): return try function(selector)
        case nil: throw .gestaltUndefinedSelector
        }
    }

    /// NewGestalt: an answer for a selector that has none, or
    /// gestaltDupSelectorErr.
    public mutating func register(_ selector: FourCharCode, _ answer: Answer) throws(MacError) {
        guard answers[selector] == nil else { throw .gestaltDuplicateSelector }
        answers[selector] = answer
    }

    /// ReplaceGestalt and SetGestaltValue: an answer in place of any
    /// before it, which is returned.
    @discardableResult
    public mutating func replace(_ selector: FourCharCode, with answer: Answer) -> Answer? {
        answers.updateValue(answer, forKey: selector)
    }

    /// DeleteGestaltValue.
    public mutating func remove(_ selector: FourCharCode) throws(MacError) {
        guard answers.removeValue(forKey: selector) != nil else { throw .gestaltUndefinedSelector }
    }

    public subscript(selector: FourCharCode) -> Int32? {
        try? response(for: selector)
    }
}

// MARK: - The standard table

public extension Gestalt {

    /// gestaltPowerPC and gestaltIntel, 'sysa''s answers.
    enum Architecture: Int32, Sendable {
        case powerPC = 2
        case intel = 10
    }

    /// The selectors a Mac OS X answers:
    ///
    /// - 'sysv': the version in BCD, 0x1058 for 10.5.8, capped at 0x1093
    ///   for later versions as Apple's is; 'sys1' to 'sys3' its parts.
    /// - 'ram ' and 'lram': the physical memory in bytes, at most 2 GB,
    ///   which an SInt32 holds.
    /// - 'sysa': the processor's architecture.
    static func standard(systemVersion: (major: Int32, minor: Int32, patch: Int32),
                         architecture: Architecture,
                         physicalMemory: Int64 = Gestalt.physicalMemory) -> Gestalt {
        let (major, minor, patch) = systemVersion
        let bcd: Int32 = major == 10 && minor <= 9 ? 0x1000 | minor << 4 | min(patch, 9) : 0x1093
        let memory = Int32(clamping: physicalMemory)
        var table = Gestalt()
        table.replace("sysv", with: .value(bcd))
        table.replace("sys1", with: .value(major))
        table.replace("sys2", with: .value(minor))
        table.replace("sys3", with: .value(patch))
        table.replace("ram ", with: .value(memory))
        table.replace("lram", with: .value(memory))
        table.replace("sysa", with: .value(architecture.rawValue))
        return table
    }

    /// The machine's physical memory in bytes.
    static var physicalMemory: Int64 {
        let pages = Int64(sysconf(Int32(_SC_PHYS_PAGES)))
        let size = Int64(sysconf(Int32(_SC_PAGESIZE)))
        return pages > 0 && size > 0 ? pages * size : 0
    }
}
