// AIFF and AIFF-C files: the common chunk's format, the sound data chunk,
// and the markers and instrument chunk that loop a sound.
//
// Ported from Pomme's SoundFormats/AIFF.cpp:
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

public extension SampledSound {

    /// The sound of an AIFF or AIFF-C file, which is what SndStartFilePlay
    /// plays. The samples are a slice of the file's bytes, not a copy. A
    /// loop is the instrument chunk's sustain loop where it has one, between
    /// markers the file has. `badFileFormat` for bytes that aren't one, that
    /// end early, have no common chunk or sound data, or name a compression
    /// type that isn't here.
    init(aiff bytes: some ContiguousBytes) throws(MacError) {
        let data = Data(sharing: bytes)
        var reader = BigEndianReader(data)
        do {
            guard try reader.read(UInt32.self) == FourCharCode("FORM").rawValue else { throw MacError.badFileFormat }
            let formSize = Int(try reader.read(UInt32.self))
            let end = min(data.count, 8 + formSize)
            let formType = FourCharCode(try reader.read(UInt32.self))
            guard formType == "AIFF" || formType == "AIFC" else { throw MacError.badFileFormat }

            var format: (channels: Int, frames: Int, bits: Int, rate: Double, encoding: SoundEncoding)?
            var samples: Range<Int>?
            var markers: [UInt16: Int] = [:]
            var baseNote = 60
            var loopMarkers: (begin: UInt16, end: UInt16)?

            while reader.offset + 8 <= end {
                let id = FourCharCode(try reader.read(UInt32.self))
                let size = Int(try reader.read(UInt32.self))
                let body = reader.offset
                guard size <= data.count - body else { throw MacError.badFileFormat }
                switch id {
                case "COMM":
                    let channels = Int(try reader.read(UInt16.self))
                    let frames = Int(try reader.read(UInt32.self))
                    let bits = Int(try reader.read(UInt16.self))
                    let rate = try reader.readExtended80().doubleValue
                    var encoding = SoundEncoding.signedBigEndian
                    if formType == "AIFC" {
                        guard let known = SoundEncoding(compressionType: FourCharCode(try reader.read(UInt32.self))) else {
                            throw MacError.badFileFormat
                        }
                        encoding = known
                    }
                    format = (channels, frames, encoding.isCompressed ? 16 : bits, rate, encoding)
                case "MARK":
                    let count = Int(try reader.read(UInt16.self))
                    for _ in 0 ..< count {
                        let marker = try reader.read(UInt16.self)
                        markers[marker] = Int(try reader.read(UInt32.self))
                        // The name, a Pascal string padded to an even length.
                        let length = Int(try reader.read(UInt8.self))
                        try reader.skip(length + (length + 1) % 2)
                    }
                case "INST":
                    baseNote = Int(try reader.read(Int8.self))
                    try reader.skip(1 + 1 + 1 + 1 + 1 + 2)              // detune to gain
                    let playMode = try reader.read(UInt16.self)
                    let begin = try reader.read(UInt16.self)
                    let loopEnd = try reader.read(UInt16.self)
                    if playMode == 1 { loopMarkers = (begin, loopEnd) }
                case "SSND":
                    let offset = Int(try reader.read(UInt32.self))
                    try reader.skip(4)                                  // blockSize
                    let start = body + 8 + offset
                    if start <= body + size { samples = start ..< body + size }
                default:
                    break
                }
                // Chunks are padded to an even length.
                let next = body + size + size % 2
                guard next <= data.count else { break }
                try reader.seek(to: next)
            }
            guard let format, let samples, format.channels >= 1, format.channels <= 256 else { throw MacError.badFileFormat }
            var loop: Range<Int>?
            if let loopMarkers, let begin = markers[loopMarkers.begin], let finish = markers[loopMarkers.end], finish > begin {
                loop = begin ..< finish
            }
            self.init(encoding: format.encoding, sampleRate: format.rate, channels: format.channels, bitsPerSample: format.bits,
                      count: format.frames, data: data[data.startIndex + samples.lowerBound ..< data.startIndex + samples.upperBound],
                      baseNote: baseNote, loop: loop)
        } catch let error as MacError {
            throw error
        } catch {
            throw .badFileFormat
        }
    }
}
