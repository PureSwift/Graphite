import Testing
import GraphiteBase

@Suite struct GestaltTests {

    @Test func standardAnswers() throws {
        let gestalt = Gestalt.standard(systemVersion: (10, 5, 8), architecture: .powerPC, physicalMemory: 512 << 20)
        #expect(try gestalt.response(for: "sysv") == 0x1058)
        #expect(gestalt["sys1"] == 10)
        #expect(gestalt["sys2"] == 5)
        #expect(gestalt["sys3"] == 8)
        #expect(gestalt["sysa"] == 2)
        #expect(gestalt["ram "] == 512 << 20)
        #expect(gestalt["lram"] == 512 << 20)
    }

    @Test func laterVersionsAreCapped() {
        #expect(Gestalt.standard(systemVersion: (14, 4, 0), architecture: .intel)["sysv"] == 0x1093)
        #expect(Gestalt.standard(systemVersion: (10, 10, 0), architecture: .intel)["sysv"] == 0x1093)
        #expect(Gestalt.standard(systemVersion: (10, 4, 11), architecture: .intel)["sysv"] == 0x1049)
    }

    @Test func memoryIsCappedAt2GB() {
        let gestalt = Gestalt.standard(systemVersion: (10, 6, 8), architecture: .intel, physicalMemory: 16 << 30)
        #expect(gestalt["ram "] == Int32.max)
        #expect(Gestalt.physicalMemory > 0)
    }

    @Test func registering() throws {
        var gestalt = Gestalt()
        #expect(throws: MacError.gestaltUndefinedSelector) { try gestalt.response(for: "qtim") }
        try gestalt.register("qtim", .value(0x0764_8000))
        #expect(throws: MacError.gestaltDuplicateSelector) { try gestalt.register("qtim", .value(0)) }
        #expect(gestalt["qtim"] == 0x0764_8000)
        let previous = gestalt.replace("qtim", with: .function { selector in Int32(bitPattern: selector.rawValue) })
        #expect(previous != nil)
        #expect(gestalt["qtim"] == Int32(bitPattern: FourCharCode("qtim").rawValue))
        try gestalt.register("fail", .function { _ throws(MacError) in throw .unimplemented })
        #expect(throws: MacError.unimplemented) { try gestalt.response(for: "fail") }
        try gestalt.remove("qtim")
        #expect(throws: MacError.gestaltUndefinedSelector) { try gestalt.remove("qtim") }
        #expect(gestalt.selectors.count == 1)
    }
}

@Suite struct ScriptManagerTests {

    @Test func romanScript() {
        #expect(ScriptManager.systemScript == 0)
        #expect(ScriptManager.scriptVariable(script: 0, selector: .enabled) == -1)
        #expect(ScriptManager.scriptVariable(script: 0, selector: .applicationFont) == 1)
        #expect(ScriptManager.scriptVariable(script: 0, selector: .systemFontSize) == 12)
        #expect(ScriptManager.scriptVariable(script: 0, selector: .monospacedFontAndSize) == 0x0016_000c)
        #expect(ScriptManager.scriptVariable(script: 0, selector: .smallFontSize) == 9)
        #expect(ScriptManager.scriptVariable(script: 0, selector: .rightToLeft) == 0)
        #expect(ScriptManager.scriptVariable(script: 0, selector: .language) == 0)
    }

    @Test func otherScriptsAreOff() {
        #expect(ScriptManager.scriptVariable(script: 1, selector: .enabled) == 0)
    }

    @Test func managerVariables() {
        #expect(ScriptManager.managerVariable(.version) == 0x0710)
        #expect(ScriptManager.managerVariable(.enabled) == 1)
        #expect(ScriptManager.managerVariable(.systemScript) == 0)
        #expect(ScriptManager.managerVariable(.regionCode) == 0)
    }
}
