// The Toolbox's result codes, as an error Graphite throws. The layer that
// exports Carbon turns it back into the OSErr or OSStatus its caller
// expects, and into ResError, MemError and QDError.

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

    // File Manager

    /// dirFulErr: the folder is full.
    static var directoryFull: MacError { MacError(-33) }
    /// dskFulErr: the disk is full.
    static var diskFull: MacError { MacError(-34) }
    /// nsvErr: no such volume.
    static var noSuchVolume: MacError { MacError(-35) }
    /// ioErr: an I/O error.
    static var io: MacError { MacError(-36) }
    /// bdNamErr: a name that isn't allowed.
    static var badName: MacError { MacError(-37) }
    /// fnOpnErr: the file isn't open.
    static var fileNotOpen: MacError { MacError(-38) }
    /// eofErr: the end of the file came first.
    static var endOfFile: MacError { MacError(-39) }
    /// posErr: a position before the start of the file.
    static var position: MacError { MacError(-40) }
    /// tmfoErr: too many files open.
    static var tooManyFilesOpen: MacError { MacError(-42) }
    /// fnfErr: the file isn't there.
    static var fileNotFound: MacError { MacError(-43) }
    /// wPrErr: the volume is locked.
    static var writeProtected: MacError { MacError(-44) }
    /// fLckdErr: the file is locked.
    static var fileLocked: MacError { MacError(-45) }
    /// fBsyErr: the file is busy, or the folder isn't empty.
    static var fileBusy: MacError { MacError(-47) }
    /// dupFNErr: an item of the name is already there.
    static var duplicateFileName: MacError { MacError(-48) }
    /// opWrErr: the file is already open for writing.
    static var openForWriting: MacError { MacError(-49) }
    /// rfNumErr: a reference number that names no open file.
    static var referenceNumber: MacError { MacError(-51) }
    /// permErr: permission denied.
    static var permission: MacError { MacError(-54) }
    /// wrPermErr: the file wasn't opened for writing.
    static var writePermission: MacError { MacError(-61) }
    /// dirNFErr: the folder isn't there.
    static var directoryNotFound: MacError { MacError(-120) }
    /// afpItemNotFound: nothing in the desktop database.
    static var itemNotFound: MacError { MacError(-1302) }
    /// errFSNoMoreItems: an iteration is done.
    static var noMoreItems: MacError { MacError(-1417) }
    /// errFSForkExists: the fork is already there.
    static var forkExists: MacError { MacError(-1421) }
    /// errFSForkNotFound: the fork isn't there.
    static var forkNotFound: MacError { MacError(-1424) }

    // Resource Manager

    /// resNotFound: no resource of the type and ID or name.
    static var resourceNotFound: MacError { MacError(-192) }
    /// resFNotFound: no open resource file of the reference number.
    static var resourceFileNotFound: MacError { MacError(-193) }
    /// addResFailed: the resource couldn't be added.
    static var addResourceFailed: MacError { MacError(-194) }
    /// rmvResFailed: the resource couldn't be removed.
    static var removeResourceFailed: MacError { MacError(-196) }
    /// resAttrErr: the resource's attributes don't allow it.
    static var resourceAttribute: MacError { MacError(-198) }
    /// mapReadErr: the resource map is damaged.
    static var mapRead: MacError { MacError(-199) }

    // Apple Event Manager

    /// procNotFound: no process of the address is running.
    static var processNotFound: MacError { MacError(-600) }
    /// errAECoercionFail: the data can't be coerced to the type.
    static var coercionFailed: MacError { MacError(-1700) }
    /// errAEDescNotFound: no descriptor of the keyword.
    static var descriptorNotFound: MacError { MacError(-1701) }
    /// errAECorruptData.
    static var corruptData: MacError { MacError(-1702) }
    /// errAEWrongDataType.
    static var wrongDataType: MacError { MacError(-1703) }
    /// errAENotAEDesc: not a descriptor.
    static var notDescriptor: MacError { MacError(-1704) }
    /// errAEBadListItem: not a list's item.
    static var badListItem: MacError { MacError(-1705) }
    /// errAENotAppleEvent.
    static var notAppleEvent: MacError { MacError(-1707) }
    /// errAEEventNotHandled: no handler took the event.
    static var eventNotHandled: MacError { MacError(-1708) }
    /// errAEReplyNotValid.
    static var replyNotValid: MacError { MacError(-1709) }
    /// errAEUnknownSendMode.
    static var unknownSendMode: MacError { MacError(-1710) }
    /// errAETimeout.
    static var appleEventTimeout: MacError { MacError(-1712) }
    /// errAEHandlerNotFound: no handler of the class and ID is installed.
    static var handlerNotFound: MacError { MacError(-1717) }
    /// errAEIllegalIndex: an index past a list's items.
    static var illegalIndex: MacError { MacError(-1719) }
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
            -33: "dirFulErr", -34: "dskFulErr", -35: "nsvErr", -36: "ioErr", -37: "bdNamErr", -38: "fnOpnErr",
            -39: "eofErr", -40: "posErr", -42: "tmfoErr", -43: "fnfErr", -44: "wPrErr", -45: "fLckdErr",
            -47: "fBsyErr", -48: "dupFNErr", -49: "opWrErr", -51: "rfNumErr", -54: "permErr", -61: "wrPermErr",
            -120: "dirNFErr", -1302: "afpItemNotFound", -1417: "errFSNoMoreItems", -1421: "errFSForkExists",
            -1424: "errFSForkNotFound", -192: "resNotFound", -193: "resFNotFound", -194: "addResFailed",
            -196: "rmvResFailed", -198: "resAttrErr", -199: "mapReadErr", -600: "procNotFound",
            -1700: "errAECoercionFail", -1701: "errAEDescNotFound", -1702: "errAECorruptData",
            -1703: "errAEWrongDataType", -1704: "errAENotAEDesc", -1705: "errAEBadListItem",
            -1707: "errAENotAppleEvent", -1708: "errAEEventNotHandled", -1709: "errAEReplyNotValid",
            -1710: "errAEUnknownSendMode", -1712: "errAETimeout", -1717: "errAEHandlerNotFound",
            -1719: "errAEIllegalIndex",
            -201: "notEnoughHardwareErr", -203: "queueFull", -204: "resProblem", -205: "badChannel",
            -206: "badFormat", -207: "notEnoughBufferSpace", -208: "badFileFormat", -209: "channelBusy",
            -210: "buffersTooSmall", -223: "siInvalidCompression",
        ]
        guard let name = names[code] else { return "\(code)" }
        return "\(name) (\(code))"
    }
}

// MARK: - Sound Manager

public extension MacError {

    /// notEnoughHardwareErr: the hardware can't do it.
    static var notEnoughHardware: MacError { MacError(-201) }
    /// queueFull: a channel's command queue has no room.
    static var queueFull: MacError { MacError(-203) }
    /// resProblem: a sound resource couldn't be loaded.
    static var soundResourceProblem: MacError { MacError(-204) }
    /// badChannel: the channel is corrupt or can't be used.
    static var badChannel: MacError { MacError(-205) }
    /// badFormat: a 'snd ' resource is corrupt or can't be used.
    static var badFormat: MacError { MacError(-206) }
    /// notEnoughBufferSpace: not enough memory for the sound.
    static var notEnoughBufferSpace: MacError { MacError(-207) }
    /// badFileFormat: a sound file is corrupt, or not AIFF or AIFF-C.
    static var badFileFormat: MacError { MacError(-208) }
    /// channelBusy: the channel is in use.
    static var channelBusy: MacError { MacError(-209) }
    /// buffersTooSmall: a double buffer's buffers are too small.
    static var buffersTooSmall: MacError { MacError(-210) }
    /// siInvalidCompression: the compression type isn't one the sound
    /// manager has.
    static var invalidCompression: MacError { MacError(-223) }
}
