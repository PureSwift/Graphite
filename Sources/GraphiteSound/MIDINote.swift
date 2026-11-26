// The pitch of the MIDI note numbers a sound's base note and a note
// command use (Inside Macintosh: Sound, Table 2-2).
//
// Ported from Pomme's SoundFormats/Midi.cpp:
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

import Foundation

public enum MIDINote {

    /// kMiddleC.
    public static var middleC: Int { 60 }

    /// The frequency in hertz of a note of 0 to 127, in equal temperament
    /// with note 69 the A of 440 Hz; 440 for a note outside that range, as
    /// the Sound Manager's table answers.
    public static func frequency(of note: Int) -> Double {
        guard (0 ..< 128).contains(note) else { return 440 }
        return 440 * pow(2, Double(note - 69) / 12)
    }
}
