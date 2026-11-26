import Testing
import GraphiteBase
import GraphiteControls

@Suite struct ControlDefinitionTests {

    private let definition = StandardControlDefinition()

    // MARK: Hit testing

    @Test func hitTesting() {
        let button = Rect(top: 0, left: 0, bottom: 20, right: 90)
        #expect(definition.hitTest(Point(v: 10, h: 10), bounds: button, kind: .button, value: 0, minimum: 0, maximum: 1, isEnabled: true) == .button)
        #expect(definition.hitTest(Point(v: 10, h: 89), bounds: button, kind: .button, value: 0, minimum: 0, maximum: 1, isEnabled: true) == .button)
        #expect(definition.hitTest(Point(v: 30, h: 10), bounds: button, kind: .button, value: 0, minimum: 0, maximum: 1, isEnabled: true) == .none)
        let box = Rect(top: 0, left: 0, bottom: 20, right: 200)
        #expect(definition.hitTest(Point(v: 10, h: 100), bounds: box, kind: .checkBox, value: 0, minimum: 0, maximum: 1, isEnabled: true) == .checkBox)
        #expect(definition.hitTest(Point(v: 10, h: 100), bounds: box, kind: .radioButton, value: 0, minimum: 0, maximum: 1, isEnabled: true) == .checkBox)
        // A disabled control is hit nowhere: its part is the whole
        // control drawn disabled.
        #expect(definition.hitTest(Point(v: 10, h: 10), bounds: button, kind: .button, value: 0, minimum: 0, maximum: 1, isEnabled: false) == .disabled)
        #expect(definition.hitTest(Point(v: 30, h: 10), bounds: button, kind: .button, value: 0, minimum: 0, maximum: 1, isEnabled: false) == .none)
    }

    @Test func scrollBarParts() {
        // A vertical bar: 200 tall, 16 wide.
        let bounds = Rect(top: 0, left: 0, bottom: 200, right: 16)
        let up = definition.rect(of: .upButton, bounds: bounds, kind: .scrollBar, value: 0, minimum: 0, maximum: 100)!
        let down = definition.rect(of: .downButton, bounds: bounds, kind: .scrollBar, value: 0, minimum: 0, maximum: 100)!
        #expect(up == Rect(top: 0, left: 0, bottom: 16, right: 16))
        #expect(down == Rect(top: 184, left: 0, bottom: 200, right: 16))
        #expect(definition.hitTest(Point(v: 8, h: 8), bounds: bounds, kind: .scrollBar, value: 0, minimum: 0, maximum: 100, isEnabled: true) == .upButton)
        #expect(definition.hitTest(Point(v: 190, h: 8), bounds: bounds, kind: .scrollBar, value: 0, minimum: 0, maximum: 100, isEnabled: true) == .downButton)
        // The thumb: 16 long at least, its place by its value, never over
        // the arrows.
        let thumb0 = definition.thumbRect(bounds: bounds, kind: .scrollBar, value: 0, minimum: 0, maximum: 100)!
        #expect(thumb0.top == 16 && thumb0.bottom == 32)
        #expect(definition.hitTest(Point(v: 20, h: 8), bounds: bounds, kind: .scrollBar, value: 0, minimum: 0, maximum: 100, isEnabled: true) == .thumb)
        let thumb100 = definition.thumbRect(bounds: bounds, kind: .scrollBar, value: 100, minimum: 0, maximum: 100)!
        #expect(thumb100.bottom == 184 && thumb100.top == 168)
        #expect(definition.hitTest(Point(v: 180, h: 8), bounds: bounds, kind: .scrollBar, value: 100, minimum: 0, maximum: 100, isEnabled: true) == .thumb)
        // The pages: below a thumb at the top, everything pages down.
        #expect(definition.hitTest(Point(v: 100, h: 8), bounds: bounds, kind: .scrollBar, value: 0, minimum: 0, maximum: 100, isEnabled: true) == .pageDown)
        let middle = definition.thumbRect(bounds: bounds, kind: .scrollBar, value: 50, minimum: 0, maximum: 100)!
        let belowThumb = Int(middle.top) + middle.height + 4
        #expect(definition.hitTest(Point(v: Int16(belowThumb), h: 8), bounds: bounds, kind: .scrollBar, value: 50, minimum: 0, maximum: 100, isEnabled: true) == .pageDown)
        // A horizontal bar: wider than tall, its arrows at the ends.
        let horizontal = Rect(top: 0, left: 0, bottom: 16, right: 200)
        let left = definition.rect(of: .upButton, bounds: horizontal, kind: .scrollBar, value: 0, minimum: 0, maximum: 100)!
        let right = definition.rect(of: .downButton, bounds: horizontal, kind: .scrollBar, value: 0, minimum: 0, maximum: 100)!
        #expect(left == Rect(top: 0, left: 0, bottom: 16, right: 16))
        #expect(right == Rect(top: 0, left: 184, bottom: 16, right: 200))
        #expect(definition.hitTest(Point(v: 8, h: 8), bounds: horizontal, kind: .scrollBar, value: 0, minimum: 0, maximum: 100, isEnabled: true) == .upButton)
        #expect(definition.hitTest(Point(v: 8, h: 190), bounds: horizontal, kind: .scrollBar, value: 0, minimum: 0, maximum: 100, isEnabled: true) == .downButton)
        #expect(definition.hitTest(Point(v: 8, h: 100), bounds: horizontal, kind: .scrollBar, value: 0, minimum: 0, maximum: 100, isEnabled: true) == .pageDown)
        // A part a control doesn't have has no rectangle.
        #expect(definition.rect(of: .thumb, bounds: Rect(top: 0, left: 0, bottom: 20, right: 90),
                                kind: .button, value: 0, minimum: 0, maximum: 1) == nil)
    }

    @Test func shortScrollBars() {
        // A bar shorter than its two arrows: no room at all between them,
        // the fallback gives the space between the arrows, which is empty.
        let short = Rect(top: 0, left: 0, bottom: 24, right: 16)
        let thumb = definition.thumbRect(bounds: short, kind: .scrollBar, value: 0, minimum: 0, maximum: 100)
        #expect(thumb == Rect(top: 16, left: 0, bottom: 8, right: 16))
        // A bar exactly as long as its arrows: the space between them is
        // nothing, as the travel is zero.
        let arrows = Rect(top: 0, left: 0, bottom: 32, right: 16)
        let squeezed = definition.thumbRect(bounds: arrows, kind: .scrollBar, value: 0, minimum: 0, maximum: 100)
        #expect(squeezed == Rect(top: 16, left: 0, bottom: 16, right: 16))
        // An empty range has no thumb at all: the bar is inactive.
        #expect(definition.thumbRect(bounds: short, kind: .scrollBar, value: 0, minimum: 5, maximum: 5) == nil)
        // A range of one: the fixed-size thumb, at the top of its travel
        // for the minimum and the bottom for the maximum.
        let one = Rect(top: 0, left: 0, bottom: 200, right: 16)
        let full = definition.thumbRect(bounds: one, kind: .scrollBar, value: 0, minimum: 0, maximum: 1)
        #expect(full?.top == 16 && full?.bottom == 32)
        let fullTop = definition.thumbRect(bounds: one, kind: .scrollBar, value: 1, minimum: 0, maximum: 1)
        #expect(fullTop?.top == 168 && fullTop?.bottom == 184)
    }

    @Test func popUpMenus() {
        // A pop-up menu is hit as a button: one part.
        let bounds = Rect(top: 0, left: 0, bottom: 20, right: 120)
        #expect(definition.hitTest(Point(v: 10, h: 60), bounds: bounds, kind: .popUpMenu, value: 0, minimum: 0, maximum: 1, isEnabled: true) == .button)
        #expect(definition.hitTest(Point(v: 30, h: 60), bounds: bounds, kind: .popUpMenu, value: 0, minimum: 0, maximum: 1, isEnabled: true) == .none)
        #expect(definition.hitTest(Point(v: 10, h: 60), bounds: bounds, kind: .popUpMenu, value: 0, minimum: 0, maximum: 1, isEnabled: false) == .disabled)
    }
}
