import Testing
import Synchronization
import GraphiteBase
import GraphiteControls

@Suite struct ControlTests {

    @Test func constants() {
        #expect(ControlPart.none.rawValue == 0)
        #expect(ControlPart.button.rawValue == 10)
        #expect(ControlPart.checkBox.rawValue == 11)
        #expect(ControlPart.upButton.rawValue == 20)
        #expect(ControlPart.downButton.rawValue == 21)
        #expect(ControlPart.pageUp.rawValue == 22)
        #expect(ControlPart.pageDown.rawValue == 23)
        #expect(ControlPart.thumb.rawValue == 129)
        #expect(ControlPart.disabled.rawValue == 254)
        #expect(ControlPart.inactive.rawValue == 255)
        // The classic's control definition IDs.
        #expect(ControlKind.button.definitionID == 0)
        #expect(ControlKind.checkBox.definitionID == 1)
        #expect(ControlKind.radioButton.definitionID == 2)
        #expect(ControlKind.scrollBar.definitionID == 16)
        #expect(ControlKind.popUpMenu.definitionID == 1008)
        #expect(ControlKind(definitionID: 0) == .button)
        #expect(ControlKind(definitionID: 8) == .button)
        #expect(ControlKind(definitionID: 1) == .checkBox)
        #expect(ControlKind(definitionID: 2) == .radioButton)
        #expect(ControlKind(definitionID: 16) == .scrollBar)
        #expect(ControlKind(definitionID: 1008) == .popUpMenu)
        // A definition the standard kinds don't answer: the host's.
        #expect(ControlKind(definitionID: 63) == nil)
        #expect(ControlKind(definitionID: 3) == nil)
        #expect(ControlKind(definitionID: 1024) == nil)
    }

    @Test func makingControls() {
        let button = Control(kind: .button, bounds: Rect(top: 10, left: 10, bottom: 30, right: 90), title: "OK")
        #expect(button.kind == .button)
        #expect(button.bounds == Rect(top: 10, left: 10, bottom: 30, right: 90))
        #expect(button.title == "OK")
        #expect(button.isVisible && button.isEnabled && button.isActive)
        #expect(button.hilitedPart == .none)
        // A button's maximum is 1, as the classic's resources kept it.
        #expect(button.maximum == 1 && button.minimum == 0 && button.value == 0)
        #expect(button.valueKind == .none)
        let checkBox = Control(kind: .checkBox, bounds: Rect(top: 0, left: 0, bottom: 20, right: 200), title: "Bold")
        #expect(checkBox.valueKind == .onOff)
        #expect(checkBox.maximum == 1 && checkBox.minimum == 0)
        let bar = Control(kind: .scrollBar, bounds: Rect(top: 0, left: 0, bottom: 200, right: 16))
        #expect(bar.valueKind == .range)
    }

    @Test func values() {
        let bar = Control(kind: .scrollBar, bounds: Rect(top: 0, left: 0, bottom: 200, right: 16))
        bar.minimum = 0
        bar.maximum = 100
        bar.setValue(50)
        #expect(bar.value == 50)
        // The value stops at its range's edges.
        bar.setValue(200)
        #expect(bar.value == 100)
        bar.setValue(-10)
        #expect(bar.value == 0)
        // An empty range pins everything to the minimum.
        bar.maximum = 0
        bar.setValue(40)
        #expect(bar.value == 0)
        // A checkbox's on-or-off.
        let checkBox = Control(kind: .checkBox, bounds: Rect(top: 0, left: 0, bottom: 20, right: 200))
        #expect(!checkBox.isOn)
        checkBox.setValue(1)
        #expect(checkBox.isOn)
    }

    @Test func thumbValues() {
        let bar = Control(kind: .scrollBar, bounds: Rect(top: 0, left: 0, bottom: 200, right: 16))
        bar.minimum = 0
        bar.maximum = 100
        bar.setValue(0)
        // The value at a point: the middle names the range's middle.
        #expect(bar.value(at: Point(v: 100, h: 8)) == 50)
        #expect(bar.value(at: Point(v: 24, h: 8)) == 0)
        #expect(bar.value(at: Point(v: 184, h: 8)) == 100)
        // Outside the bar pins to the edges.
        #expect(bar.value(at: Point(v: -20, h: 8)) == 0)
        #expect(bar.value(at: Point(v: 300, h: 8)) == 100)
        // A control without a thumb has no value at a point.
        let button = Control(kind: .button, bounds: Rect(top: 0, left: 0, bottom: 20, right: 90))
        #expect(button.value(at: Point(v: 10, h: 10)) == nil)
        // An empty range: the bar is inactive, with no thumb to drag.
        bar.maximum = 0
        #expect(bar.value(at: Point(v: 100, h: 8)) == nil)
    }

    @Test func states() {
        let button = Control(kind: .button, bounds: Rect(top: 0, left: 0, bottom: 20, right: 90), title: "OK")
        #expect(button.isLive)
        button.hide()
        #expect(!button.isVisible && !button.isLive)
        button.show()
        button.disable()
        #expect(!button.isEnabled && !button.isLive)
        button.enable()
        button.deactivate()
        #expect(!button.isActive && !button.isLive)
        button.activate()
        #expect(button.isLive)
        // HiliteControl's part, drawn pressed.
        button.hilite(.button)
        #expect(button.hilitedPart == .button)
        button.hilite(.none)
        #expect(button.hilitedPart == .none)
        // Whatever the program keeps with the control, and its command and
        // its identifier.
        button.reference = 129
        #expect(button.reference == 129)
        button.commandID = "ok  "
        #expect(button.commandID == "ok  ")
        button.identifier = (signature: "com.", id: 5)
        #expect(button.identifier?.signature == "com.")
        #expect(button.identifier?.id == 5)
        // The action procedure, called by the host as it tracks. The part
        // it was called with, kept through a lock the closure can hold.
        let called = Mutex<[ControlPart]>([])
        button.action = { part, _ in called.withLock { $0.append(part) } }
        button.action?(.button, 0)
        #expect(called.withLock { $0 } == [.button])
    }

    @Test func movingAndSizing() {
        let button = Control(kind: .button, bounds: Rect(top: 10, left: 20, bottom: 30, right: 90), title: "OK")
        button.move(h: 100, v: 50)
        #expect(button.bounds == Rect(top: 50, left: 100, bottom: 70, right: 170))
        button.size(width: 40, height: 25)
        #expect(button.bounds == Rect(top: 50, left: 100, bottom: 75, right: 140))
    }

    @Test func titles() {
        let button = Control(kind: .button, bounds: Rect(top: 0, left: 0, bottom: 20, right: 90), title: "Répéter")
        #expect(button.title == "Répéter")
        button.title = "Annuler"
        #expect(button.title == "Annuler")
    }
}
