import Testing
import GraphiteBase
import GraphiteTasks

@Suite struct AbsoluteTimeTests {

    @Test func durations() {
        #expect(MacDuration.milliseconds(5).nanoseconds == 5_000_000)
        #expect(MacDuration.microseconds(5).rawValue == -5)
        #expect(MacDuration.microseconds(5).nanoseconds == 5000)
        #expect(MacDuration(rawValue: Int32.min).nanoseconds == 2_147_483_648_000)
        #expect(MacDuration.forever.isForever)
        #expect(MacDuration.immediate.nanoseconds == 0)
    }

    @Test func absoluteToDuration() {
        #expect(MacDuration(nanoseconds: 2_500_000).rawValue == 2)
        #expect(MacDuration(nanoseconds: 999_999).rawValue == -999)
        #expect(MacDuration(nanoseconds: 0).rawValue == 0)
        #expect(MacDuration(nanoseconds: .max).rawValue == .max)
    }

    @Test func addDurationToAbsolute() {
        let time = AbsoluteTime(nanoseconds: 1000)
        #expect((time + .milliseconds(1)).nanoseconds == 1_001_000)
        #expect((time + .microseconds(1)).nanoseconds == 2000)
        #expect(AbsoluteTime(nanoseconds: 5) - AbsoluteTime(nanoseconds: 2) == 3)
        #expect(AbsoluteTime(nanoseconds: 2) - AbsoluteTime(nanoseconds: 5) == 0)
    }

    @Test func upTimeAdvances() {
        let start = AbsoluteTime.now
        delay(until: start + .milliseconds(20))
        let elapsed = AbsoluteTime.now - start
        #expect(elapsed >= 20_000_000)
        #expect(elapsed < 2_000_000_000)
        // A time already past doesn't wait.
        delay(until: start)
    }
}
