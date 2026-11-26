import Testing
import GraphiteSound

@Suite struct MIDINoteTests {

    @Test func aboveAndBelowTheA() {
        #expect(MIDINote.frequency(of: 69) == 440)
        #expect(abs(MIDINote.frequency(of: 81) - 880) < 1e-9)
        #expect(abs(MIDINote.frequency(of: 57) - 220) < 1e-9)
        #expect(abs(MIDINote.frequency(of: 45) - 110) < 1e-9)
    }

    @Test func middleC() {
        #expect(MIDINote.middleC == 60)
        #expect(abs(MIDINote.frequency(of: MIDINote.middleC) - 261.6255653) < 1e-6)
    }

    @Test func theEnds() {
        #expect(abs(MIDINote.frequency(of: 0) - 8.1757989) < 1e-6)
        #expect(abs(MIDINote.frequency(of: 127) - 12543.8539514) < 1e-4)
    }

    @Test func eachSemitoneIsTheTwelfthRootOfTwoAbove() {
        for note in 0 ..< 127 {
            let ratio = MIDINote.frequency(of: note + 1) / MIDINote.frequency(of: note)
            #expect(abs(ratio - 1.0594630943592953) < 1e-12)
        }
    }

    @Test func notesOutsideTheTableAre440() {
        #expect(MIDINote.frequency(of: -1) == 440)
        #expect(MIDINote.frequency(of: 128) == 440)
        #expect(MIDINote.frequency(of: .max) == 440)
        #expect(MIDINote.frequency(of: .min) == 440)
    }
}
