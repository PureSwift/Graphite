import Testing
import GraphiteBase
import GraphiteControls

@Suite struct ControlResourceTests {

    /// A 'CNTL' resource's bytes: the rectangle, the initial setting, the
    /// visibility, the fill, the maximum, the minimum, the definition ID,
    /// the reference, and the title.
    private func controlBytes(bounds: Rect, value: Int16, visible: Bool, maximum: Int16, minimum: Int16,
                              definitionID: Int16, reference: Int32, title: String) -> [UInt8] {
        var bytes: [UInt8] = []
        // The rectangle, then the setting, the visibility, the fill, the
        // maximum, the minimum, the definition ID — the order the resource
        // keeps.
        for value in [bounds.top, bounds.left, bounds.bottom, bounds.right] {
            let raw = UInt16(bitPattern: value)
            bytes += [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        }
        let setting = UInt16(bitPattern: value)
        bytes += [UInt8(setting >> 8), UInt8(setting & 0xFF)]
        bytes += [visible ? 1 : 0, 0]
        for field in [maximum, minimum, definitionID] {
            let raw = UInt16(bitPattern: field)
            bytes += [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        }
        let referenceRaw = UInt32(bitPattern: reference)
        bytes += [UInt8(referenceRaw >> 24), UInt8(referenceRaw >> 16 & 0xFF),
                  UInt8(referenceRaw >> 8 & 0xFF), UInt8(referenceRaw & 0xFF)]
        let titleBytes = MacRoman.encode(title)!
        bytes += [UInt8(titleBytes.count)] + titleBytes
        return bytes
    }

    @Test func readingControls() throws {
        // A visible OK button.
        let button = try Control.make(bytes: controlBytes(bounds: Rect(top: 10, left: 10, bottom: 30, right: 90),
                                                           value: 0, visible: true, maximum: 1, minimum: 0,
                                                           definitionID: 0, reference: 0, title: "OK"))
        #expect(button.kind == .button)
        #expect(button.bounds == Rect(top: 10, left: 10, bottom: 30, right: 90))
        #expect(button.title == "OK")
        #expect(button.isVisible)
        #expect(button.maximum == 1 && button.minimum == 0 && button.value == 0)
        #expect(button.reference == 0)
        // A checkbox, on, with a useWFont variation.
        let checkBox = try Control.make(bytes: controlBytes(bounds: Rect(top: 40, left: 10, bottom: 60, right: 200),
                                                            value: 1, visible: true, maximum: 1, minimum: 0,
                                                            definitionID: 1, reference: 0, title: "Bold"))
        #expect(checkBox.kind == .checkBox && checkBox.isOn)
        // A radio button.
        let radio = try Control.make(bytes: controlBytes(bounds: Rect(top: 60, left: 10, bottom: 80, right: 200),
                                                         value: 0, visible: true, maximum: 1, minimum: 0,
                                                         definitionID: 2, reference: 0, title: "Small"))
        #expect(radio.kind == .radioButton && !radio.isOn)
        // A horizontal scroll bar, its range and its place in it.
        let bar = try Control.make(bytes: controlBytes(bounds: Rect(top: 0, left: 0, bottom: 16, right: 200),
                                                        value: 30, visible: true, maximum: 100, minimum: 0,
                                                        definitionID: 16, reference: 0, title: ""))
        #expect(bar.kind == .scrollBar)
        #expect(bar.value == 30 && bar.minimum == 0 && bar.maximum == 100)
        // An invisible pop-up menu, holding its menu's resource ID in its
        // minimum, as the classic kept it.
        let popUp = try Control.make(bytes: controlBytes(bounds: Rect(top: 0, left: 0, bottom: 20, right: 120),
                                                          value: 1, visible: false, maximum: 60, minimum: 128,
                                                          definitionID: 1008, reference: 0, title: "Font"))
        #expect(popUp.kind == .popUpMenu)
        #expect(!popUp.isVisible)
        #expect(popUp.minimum == 128 && popUp.maximum == 60)
        // Bytes past the title are ignored.
        var extra = controlBytes(bounds: Rect(top: 0, left: 0, bottom: 20, right: 90), value: 0, visible: true,
                                 maximum: 1, minimum: 0, definitionID: 0, reference: 0, title: "OK")
        extra += [0, 128]
        #expect(try Control.make(bytes: extra).title == "OK")
    }

    @Test func damagedResources() {
        // Cut off inside the rectangle.
        #expect(throws: MacError.parameter) {
            _ = try Control.make(bytes: [0, 0, 0, 0, 0, 100])
        }
        // Nothing at all.
        #expect(throws: MacError.parameter) {
            _ = try Control.make(bytes: [])
        }
        // Cut off inside the reference value.
        #expect(throws: MacError.parameter) {
            _ = try Control.make(bytes: [0, 0, 0, 10, 0, 20, 0, 30, 0, 0, 1, 0, 1, 0, 0, 0, 16, 0, 0, 0, 0, 1])
        }
        // A definition ID the standard kinds don't answer and no host
        // definition was given for.
        #expect(throws: MacError.parameter) {
            _ = try Control.make(bytes: controlBytes(bounds: Rect(top: 0, left: 0, bottom: 20, right: 90),
                                                     value: 0, visible: true, maximum: 1, minimum: 0,
                                                     definitionID: 63, reference: 0, title: "?"))
        }
    }
}
