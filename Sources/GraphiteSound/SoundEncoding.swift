// How a sampled sound's samples are stored: the compression types a 'snd '
// resource or an AIFF-C file names.

import GraphiteBase

public enum SoundEncoding: Hashable, Sendable {

    /// 'raw ': 8-bit, offset binary, where silence is 128.
    case unsigned8

    /// 'twos', and AIFF's 'NONE': signed, big-endian, of 8, 16, 24 or 32 bits.
    case signedBigEndian

    /// 'sowt': signed, little-endian.
    case signedLittleEndian

    /// 'ulaw': G.711 µ-law, a byte a sample.
    case ulaw

    /// 'alaw': G.711 A-law, a byte a sample.
    case alaw

    /// 'ima4': Apple's IMA ADPCM, 4:1.
    case ima4

    /// 'MAC3': MACE 3:1.
    case mace3

    /// 'MAC6': MACE 6:1.
    case mace6

    /// The encoding a compression type names: nil for one that isn't here.
    public init?(compressionType: FourCharCode) {
        switch compressionType {
        case "raw ": self = .unsigned8
        case "twos", "NONE": self = .signedBigEndian
        case "sowt": self = .signedLittleEndian
        case "ulaw": self = .ulaw
        case "alaw": self = .alaw
        case "ima4": self = .ima4
        case "MAC3": self = .mace3
        case "MAC6": self = .mace6
        default: return nil
        }
    }

    /// The compression type of 'snd ' resources and AIFF-C files.
    public var compressionType: FourCharCode {
        switch self {
        case .unsigned8: "raw "
        case .signedBigEndian: "twos"
        case .signedLittleEndian: "sowt"
        case .ulaw: "ulaw"
        case .alaw: "alaw"
        case .ima4: "ima4"
        case .mace3: "MAC3"
        case .mace6: "MAC6"
        }
    }

    /// Whether the samples are in packets of a codec's, not one after another.
    public var isCompressed: Bool { packet != nil }

    /// A compressed channel's packet: the bytes it takes and the samples it
    /// holds. Nil for uncompressed samples.
    public var packet: (bytes: Int, frames: Int)? {
        switch self {
        case .ulaw, .alaw: (1, 1)
        case .ima4: (34, 64)
        case .mace3: (2, 6)
        case .mace6: (1, 6)
        case .unsigned8, .signedBigEndian, .signedLittleEndian: nil
        }
    }

    /// The codec that decodes the encoding; nil for uncompressed samples and
    /// for MACE, which isn't decoded yet.
    public var codec: (any SoundCodec)? {
        switch self {
        case .ulaw: XLawCodec(.mu)
        case .alaw: XLawCodec(.a)
        case .ima4: IMA4Codec()
        case .unsigned8, .signedBigEndian, .signedLittleEndian, .mace3, .mace6: nil
        }
    }
}
