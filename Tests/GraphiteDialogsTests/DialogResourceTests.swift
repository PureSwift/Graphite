import Testing
import GraphiteBase
import GraphiteDialogs

@Suite struct DialogResourceTests {
    @Test func packedAlertStages() throws {
        // Four distinct nibbles in the order stored by Rez: stages 4 to 1.
        let bytes: [UInt8] = [0, 1, 0, 2, 0, 40, 0, 80, 0, 128, 0xC9, 0x65, 0, 0]
        let alert = try AlertResource(bytes: bytes)
        #expect(alert.stages.map(\.bits) == [5, 6, 9, 12])
        #expect(alert.stages[0].isDrawn)
        #expect(alert.stages[0].soundCount == 1)
        #expect(alert.stages[2].secondItemIsDefault)
        #expect(alert.bytes == bytes)
        let oldAlert = try AlertResource(bytes: Array(bytes.prefix(12)))
        #expect(oldAlert.position == 0)
    }

    @Test func emptyItemList() throws {
        let list = try DialogItemList(bytes: [0xFF, 0xFF])
        #expect(list.count == 0)
        #expect(list.bytes == [0xFF, 0xFF])
    }
}
