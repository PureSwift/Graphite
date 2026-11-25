import Testing
import GraphiteBase

@Suite struct MacErrorTests {

    @Test func checkThrowsAllButNoErr() throws {
        try MacError.check(0)
        #expect(throws: MacError.parameter) { try MacError.check(-50) }
        #expect(MacError.success.isSuccess)
        #expect(!MacError.memoryFull.isSuccess)
    }

    @Test func codes() {
        #expect(MacError.parameter.code == -50)
        #expect(MacError.memoryFull.code == -108)
        #expect(MacError.gestaltUndefinedSelector.code == -5551)
        #expect(MacError.mpTimeout.code == -29296)
        #expect(MacError.mpDeleted.code == -29295)
    }

    @Test func descriptionNamesKnownCodes() {
        #expect(MacError.parameter.description == "paramErr (-50)")
        #expect(MacError(-12345).description == "-12345")
    }

    @Test func typedThrows() {
        func fail() throws(MacError) { throw .nilHandle }
        do {
            try fail()
            Issue.record("didn't throw")
        } catch {
            #expect(error == .nilHandle)
        }
    }
}
