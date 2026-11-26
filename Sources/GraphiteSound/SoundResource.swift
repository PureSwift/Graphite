// 'snd ' resources: format 1 and 2, the commands that point at a sampled
// sound header, and the standard, compressed and extended headers.
//
// Ported from Pomme's SoundFormats/SoundFormats.cpp:
// Copyright (c) 2020 Iliyas Jorio
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import protocol Foundation.ContiguousBytes
import struct Foundation.Data
import GraphiteBase

public enum SoundResource {

    public static var resourceType: FourCharCode { "snd " }

    /// The synthesizer of sampled sounds, the only one read here.
    private static let sampledSynth: UInt16 = 5

    /// The sound commands that carry a sampled sound header: soundCmd and
    /// bufferCmd.
    private static let headerCommands: Set<UInt16> = [80, 81]

    /// initMACE6 in a format 1 resource's init bits: a compressed header
    /// that names no compression is MACE 6:1 then, and MACE 3:1 otherwise.
    static let initMACE6: UInt32 = 0x0400

    /// GetSoundHeaderOffset: where the sampled sound header is in a 'snd '
    /// resource, from its start. `badFormat` for a resource of another
    /// format, or with no command that has sound data.
    public static func headerOffset(in bytes: some ContiguousBytes) throws(MacError) -> Int {
        try locate(in: Data(sharing: bytes)).offset
    }

    /// The header's offset, and the init bits of a format 1 resource's
    /// sampled synthesizer, which the header can need.
    static func locate(in data: Data) throws(MacError) -> (offset: Int, initBits: UInt32) {
        var reader = BigEndianReader(data)
        do {
            var initBits: UInt32 = 0
            switch try reader.read(UInt16.self) {
            case 1:
                let modifiers = Int(try reader.read(UInt16.self))
                var sampled = false
                for _ in 0 ..< modifiers {
                    let synth = try reader.read(UInt16.self)
                    let bits = try reader.read(UInt32.self)
                    if synth == sampledSynth {
                        sampled = true
                        initBits = bits
                    }
                }
                guard sampled else { throw MacError.badFormat }
            case 2:
                try reader.skip(2)                                      // the reference count, the program's
            default:
                throw MacError.badFormat
            }
            let commands = Int(try reader.read(UInt16.self))
            for _ in 0 ..< commands {
                let command = try reader.read(UInt16.self)
                try reader.skip(2)                                      // param1
                let parameter = Int(try reader.read(UInt32.self))
                // With its high bit set, a command's param2 is an offset
                // from the resource's start to its sound data.
                if command & 0x8000 != 0, headerCommands.contains(command & 0x7FFF) {
                    guard parameter < data.count else { throw MacError.badFormat }
                    return (parameter, initBits)
                }
            }
            throw MacError.badFormat
        } catch let error as MacError {
            throw error
        } catch {
            throw .badFormat
        }
    }
}

public extension SampledSound {

    /// The first sampled sound of a 'snd ' resource.
    init(snd bytes: some ContiguousBytes) throws(MacError) {
        let data = Data(sharing: bytes)
        let (offset, initBits) = try SoundResource.locate(in: data)
        try self.init(header: data[data.startIndex + offset ..< data.endIndex], initBits: initBits)
    }

    /// A sampled sound header and the samples after it: standard (8-bit
    /// mono), compressed or extended. `initBits` are the init bits of the
    /// resource that has it, for a compressed header that doesn't say
    /// which MACE it is. A sound with less data than its header says has
    /// the data there is. `badFormat` for a header that isn't one.
    init(header bytes: some ContiguousBytes, initBits: UInt32 = 0) throws(MacError) {
        let data = Data(sharing: bytes)
        var reader = BigEndianReader(data)
        do {
            guard try reader.read(UInt32.self) == 0 else { throw MacError.badFormat }   // samplePtr
            let length = Int(try reader.read(Int32.self))               // the byte count, or the channels
            let rate = Double(try reader.read(UInt32.self)) / 65536
            let loopStart = Int(try reader.read(UInt32.self))
            let loopEnd = Int(try reader.read(UInt32.self))
            let encode = try reader.read(UInt8.self)
            let baseNote = Int(try reader.read(UInt8.self))
            let encoding: SoundEncoding
            let channels: Int
            let bits: Int
            let count: Int
            switch encode {
            case 0x00:
                encoding = .unsigned8
                channels = 1
                bits = 8
                count = length
            case 0xFE:
                count = Int(try reader.read(Int32.self))
                try reader.skip(14)                                     // AIFFSampleRate, markerChunk
                let type = try reader.read(UInt32.self)
                try reader.skip(20)                                     // futureUse2 to sampleSize
                if type == 0 {
                    encoding = initBits & SoundResource.initMACE6 != 0 ? .mace6 : .mace3
                } else if let known = SoundEncoding(compressionType: FourCharCode(type)), known.isCompressed {
                    encoding = known
                } else {
                    throw MacError.invalidCompression
                }
                channels = length
                bits = 16
            case 0xFF:
                count = Int(try reader.read(Int32.self))
                try reader.skip(22)                                     // AIFFSampleRate to AESRecording
                bits = Int(try reader.read(Int16.self))
                try reader.skip(14)                                     // futureUse1 to futureUse4
                encoding = bits == 8 ? .unsigned8 : .signedBigEndian
                channels = length
            default:
                throw MacError.badFormat
            }
            // Bounded, so the arithmetic below can't overflow on a 32-bit CPU.
            guard channels >= 1, channels <= 256, count >= 0, bits >= 1, bits <= 64 else { throw MacError.badFormat }
            let width = encoding.packet?.bytes ?? (bits + 7) / 8
            let size = Int(clamping: Int64(channels) * Int64(count) * Int64(width))
            let start = data.startIndex + reader.offset
            let end = start + min(size, data.endIndex - start)
            self.init(encoding: encoding, sampleRate: rate, channels: channels, bitsPerSample: bits, count: count,
                      data: data[start ..< end], baseNote: baseNote, loop: loopEnd > loopStart ? loopStart ..< loopEnd : nil)
        } catch let error as MacError {
            throw error
        } catch {
            throw .badFormat
        }
    }

    /// The sound as a format 1 'snd ' resource: a sampled synthesizer, one
    /// bufferCmd and the header and samples it points at, in the standard
    /// header where it can be (8-bit mono), the compressed one for MACE and
    /// the other codecs, and the extended one for other uncompressed sound.
    var sndResource: [UInt8] {
        var writer = BigEndianWriter()
        var initBits: UInt32 = channels == 1 ? 0x0080 : (channels == 2 ? 0x00C0 : 0)
        if encoding == .mace3 { initBits |= 0x0300 }
        if encoding == .mace6 { initBits |= SoundResource.initMACE6 }
        writer.write(UInt16(1))                                         // format
        writer.write(UInt16(1))                                         // one modifier
        writer.write(UInt16(5))                                         // sampledSynth
        writer.write(initBits)
        writer.write(UInt16(1))                                         // one command
        writer.write(UInt16(0x8051))                                    // bufferCmd, its param2 an offset
        writer.write(UInt16(0))
        writer.write(UInt32(20))                                        // the header, after these 20 bytes
        writer.write(UInt32(0))                                         // samplePtr
        let isStandard = encoding == .unsigned8 && channels == 1 && bitsPerSample == 8
        writer.write(Int32(clamping: isStandard ? count : channels))
        writer.write(UInt32(sampleRate.isFinite ? min(max(sampleRate, 0), 65535) * 65536 : 0))
        writer.write(UInt32(clamping: loop?.lowerBound ?? 0))
        writer.write(UInt32(clamping: loop?.upperBound ?? 0))
        writer.write(UInt8(isStandard ? 0x00 : (encoding.isCompressed ? 0xFE : 0xFF)))
        writer.write(UInt8(clamping: baseNote))
        if !isStandard {
            writer.write(Int32(clamping: count))
            writer.write(bytes: Extended80(sampleRate).bytes)           // AIFFSampleRate
            if encoding.isCompressed {
                writer.writeZeros(4)                                    // markerChunk
                writer.write(encoding.compressionType.rawValue)
                writer.writeZeros(4 + 4 + 4)                            // futureUse2, stateVars, leftOverSamples
                writer.write(Int16(-1))                                 // compressionID: fixedCompression
                writer.writeZeros(2 + 2)                                // packetSize, snthID
                writer.write(Int16(16))                                 // sampleSize
            } else {
                writer.writeZeros(4 + 4 + 4)                            // markerChunk, instrumentChunks, AESRecording
                writer.write(Int16(clamping: bitsPerSample))            // sampleSize
                writer.writeZeros(14)                                   // futureUse1 to futureUse4
            }
        }
        writer.write(bytes: data)
        return writer.bytes
    }
}
