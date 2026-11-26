import Testing
import GraphiteBase
import GraphiteMenus

@Suite struct MenuDefinitionTests {

    /// The width of a text in the Chicago look: wide.
    private func measure(_ text: PascalString) -> Int16 {
        Int16(text.count * 8)
    }

    @Test func standardSizes() {
        let definition = StandardMenuDefinition()
        #expect(definition.menuBarHeight == 20)
        #expect(definition.itemHeight == 16)
        #expect(definition.menuHeight(itemCount: 5) == 80)
        #expect(definition.menuHeight(itemCount: 0) == 0)
        // A menu's width: the margins, the widest text, and a column each
        // for the marks, icons and keys that are there.
        var items = [MenuItem(text: "About SurfWriter…"),
                     MenuItem(text: "Cut"),
                     MenuItem(text: "Paste")]
        #expect(definition.menuWidth(of: items, attributes: [], measuring: measure) == 2 + 17 * 8 + 2)
        items[0].icon = 1
        #expect(definition.menuWidth(of: items, attributes: [], measuring: measure) == 2 + 16 + 17 * 8 + 2)
        items[1].mark = .checkmark
        #expect(definition.menuWidth(of: items, attributes: [], measuring: measure) == 2 + 16 + 16 + 17 * 8 + 2)
        items[2].key = UInt8(ascii: "V")
        #expect(definition.menuWidth(of: items, attributes: [], measuring: measure) == 2 + 16 + 16 + 17 * 8 + 16 + 2)
        // kMenuAttrExcludesMarkColumn keeps none for the marks.
        #expect(definition.menuWidth(of: items, attributes: [.excludesMarkColumn], measuring: measure)
            == 2 + 16 + 17 * 8 + 16 + 2)
        // An empty menu: its margins alone.
        #expect(definition.menuWidth(of: [], attributes: [], measuring: measure) == 4)
        // A submenu's $1B is no key column.
        var submenu = [MenuItem(text: "Sizes")]
        submenu[0].key = 0x1B
        #expect(definition.menuWidth(of: submenu, attributes: [], measuring: measure) == 2 + 5 * 8 + 2)
    }

    @Test func itemsGeometry() {
        let definition = StandardMenuDefinition()
        let bounds = Rect(top: 40, left: 100, bottom: 120, right: 200)
        #expect(definition.itemRect(at: 0, in: bounds) == Rect(top: 40, left: 100, bottom: 56, right: 200))
        #expect(definition.itemRect(at: 2, in: bounds) == Rect(top: 72, left: 100, bottom: 88, right: 200))
        // mChooseMsg: the item a point is on, from the first.
        #expect(definition.hitTest(Point(v: 45, h: 130), in: bounds, itemCount: 5) == 0)
        #expect(definition.hitTest(Point(v: 71, h: 130), in: bounds, itemCount: 5) == 1)
        #expect(definition.hitTest(Point(v: 100, h: 130), in: bounds, itemCount: 5) == 3)
        // Past the last item there is, or outside the menu, none.
        #expect(definition.hitTest(Point(v: 119, h: 130), in: bounds, itemCount: 2) == nil)
        #expect(definition.hitTest(Point(v: 30, h: 130), in: bounds, itemCount: 5) == nil)
        #expect(definition.hitTest(Point(v: 50, h: 99), in: bounds, itemCount: 5) == nil)
        #expect(definition.hitTest(Point(v: 50, h: 201), in: bounds, itemCount: 5) == nil)
        // The rectangle of an item past the last: below them all.
        #expect(definition.itemRect(at: 5, in: bounds).top == 40 + 5 * 16)
    }
}
