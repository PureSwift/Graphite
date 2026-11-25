// The Toolbox's result codes, as an error Graphite throws. Perry turns it
// back into the OSErr or OSStatus its caller expects, and into ResError,
// MemError and QDError.

/// A Mac OS result code. Zero, noErr, is success; Graphite throws only the
/// others.
public struct MacError: Error, Hashable, Sendable {

    public var code: Int32

    public init(_ code: Int32) {
        self.code = code
    }

    public init(code: Int32) {
        self.code = code
    }

    /// noErr.
    public static var success: MacError { MacError(0) }

    public var isSuccess: Bool { code == 0 }

    /// Throws the code unless it is noErr.
    public static func check(_ code: Int32) throws(MacError) {
        guard code != 0 else { return }
        throw MacError(code)
    }
}

// MARK: - Codes

public extension MacError {

    // General

    /// qErr: a queue element wasn't found.
    static var queue: MacError { MacError(-1) }
    /// unimpErr: a trap or call that isn't implemented.
    static var unimplemented: MacError { MacError(-4) }
    /// paramErr: a parameter is wrong.
    static var parameter: MacError { MacError(-50) }
    /// userCanceledErr.
    static var userCanceled: MacError { MacError(-128) }

    // Memory Manager

    /// memFullErr: not enough memory.
    static var memoryFull: MacError { MacError(-108) }
    /// nilHandleErr: a handle that is nil.
    static var nilHandle: MacError { MacError(-109) }

    // Gestalt

    /// gestaltUndefSelectorErr: no answer for the selector.
    static var gestaltUndefinedSelector: MacError { MacError(-5551) }
    /// gestaltDupSelectorErr: the selector already has an answer.
    static var gestaltDuplicateSelector: MacError { MacError(-5552) }
    /// gestaltLocationErr: the function isn't in the system heap.
    static var gestaltLocation: MacError { MacError(-5553) }

    // Multiprocessing Services

    /// kMPInvalidIDErr: the task, queue, event, semaphore or region was
    /// deleted or never made.
    static var mpInvalidID: MacError { MacError(-29299) }
    /// kMPInsufficientResourcesErr.
    static var mpInsufficientResources: MacError { MacError(-29298) }
    /// kMPTaskAbortedErr.
    static var mpTaskAborted: MacError { MacError(-29297) }
    /// kMPTimeoutErr: the wait's time ran out.
    static var mpTimeout: MacError { MacError(-29296) }
    /// kMPDeletedErr: what was waited on was deleted.
    static var mpDeleted: MacError { MacError(-29295) }
}

extension MacError: CustomStringConvertible {

    /// The code with its Toolbox name when Graphite knows it:
    /// "paramErr (-50)".
    public var description: String {
        let names: [Int32: String] = [
            0: "noErr", -1: "qErr", -4: "unimpErr", -50: "paramErr", -108: "memFullErr", -109: "nilHandleErr",
            -128: "userCanceledErr", -5551: "gestaltUndefSelectorErr", -5552: "gestaltDupSelectorErr",
            -5553: "gestaltLocationErr", -29299: "kMPInvalidIDErr", -29298: "kMPInsufficientResourcesErr",
            -29297: "kMPTaskAbortedErr", -29296: "kMPTimeoutErr", -29295: "kMPDeletedErr",
        ]
        guard let name = names[code] else { return "\(code)" }
        return "\(name) (\(code))"
    }
}
