import Testing
import GraphiteBase
import GraphiteQuickDraw
import GraphiteWindows

@Suite struct WindowTests {

    /// Windows by identity, in their order.
    private func listed(_ windows: [Window]) -> [ObjectIdentifier] {
        windows.map(ObjectIdentifier.init)
    }

    /// A 640×480 screen: a 20-pixel menu bar above a 620-pixel desktop.
    private func makeManager() -> WindowManager {
        WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    }

    @Test func classesAndAttributes() {
        #expect(WindowClass(rawValue: 6) == .document)
        #expect(WindowClass(rawValue: 20) == .drawer)
        #expect(WindowClass.floating.isFloating && !WindowClass.document.isFloating)
        #expect(WindowClass.overlay.layer > WindowClass.alert.layer)
        #expect(WindowClass.alert.layer > WindowClass.floating.layer)
        #expect(WindowClass.floating.layer > WindowClass.document.layer)
        #expect(WindowClass.document.activationScope == .all)
        #expect(WindowClass.floating.activationScope == .independent)
        #expect(WindowClass.help.activationScope == .none)
        #expect(WindowAttributes.closeBox.rawValue == 1)
        #expect(WindowAttributes.horizontalZoom.rawValue == 2)
        #expect(WindowAttributes.verticalZoom.rawValue == 4)
        #expect(WindowAttributes.collapseBox.rawValue == 8)
        #expect(WindowAttributes.resizable.rawValue == 16)
        #expect(WindowAttributes.fullZoom == [.horizontalZoom, .verticalZoom])
        #expect(WindowAttributes.standardDocument == [.closeBox, .fullZoom, .collapseBox, .resizable])
        #expect(WindowAttributes.standardFloating == [.closeBox, .collapseBox])
        #expect(WindowRegion.structure.rawValue == 32 && WindowRegion.content.rawValue == 33)
        #expect(WindowRegion.globalPort.rawValue == 40)
        #expect(WindowPart.content.rawValue == 3 && WindowPart.drag.rawValue == 4)
        #expect(WindowPart.grow.rawValue == 5 && WindowPart.goAway.rawValue == 6)
        #expect(WindowPart.zoomIn.rawValue == 7 && WindowPart.zoomOut.rawValue == 8)
        #expect(WindowPart.collapseBox.rawValue == 11 && WindowPart.structure.rawValue == 15)
        #expect(WindowPositionMethod(rawValue: 4) == .cascadeOnMainScreen)
    }

    @Test func newWindow() throws {
        let manager = makeManager()
        let window = try manager.newWindow(attributes: .standardDocument,
                                           bounds: Rect(top: 40, left: 40, bottom: 140, right: 140), title: "Report")
        // The structure surrounds the content: a title bar above, a
        // four-pixel frame around the rest.
        #expect(window.structureBounds == Rect(top: 20, left: 36, bottom: 144, right: 144))
        #expect(window.contentBounds == Rect(top: 40, left: 40, bottom: 140, right: 140))
        #expect(window.port.portRect == Rect(top: 0, left: 0, bottom: 100, right: 100))
        // A new window's buffer is white, and nothing has been shown.
        #expect(window.pixels.color(at: Point(v: 50, h: 50)) == .white)
        #expect(window.title == "Report")
        #expect(window.kindCode == 8)
        #expect(window.isVisible == false)
        #expect(window.visibleRegion.isEmpty)
        #expect(window.updateRegion.isEmpty)
        #expect(listed(manager.windows) == listed([window]))
        // The frame of a standard document window.
        #expect(window.features.contains(.hasTitleBar))
        #expect(window.features.contains(.canGrow))
        #expect(window.features.contains(.canZoom))
        #expect(window.features.contains(.canCollapse))
    }

    @Test func emptyBounds() {
        let manager = makeManager()
        #expect(throws: MacError.parameter) {
            try manager.newWindow(bounds: .zero)
        }
    }

    @Test func framelessClasses() throws {
        let manager = makeManager()
        let simple = try manager.newWindow(windowClass: .simple, bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        #expect(simple.contentBounds == simple.structureBounds)
        #expect(!simple.features.contains(.hasTitleBar))
        let plain = try manager.newWindow(windowClass: .plain, bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        #expect(plain.structureBounds == Rect(top: 39, left: 39, bottom: 141, right: 141))
        #expect(plain.contentBounds == Rect(top: 40, left: 40, bottom: 140, right: 140))
        let palette = try manager.newWindow(windowClass: .floating, attributes: .standardFloating,
                                           bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        #expect(palette.structureBounds == Rect(top: 23, left: 40, bottom: 140, right: 140))
        #expect(palette.contentBounds == Rect(top: 40, left: 40, bottom: 140, right: 140))
        let dialog = try manager.newWindow(windowClass: .modal, bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        #expect(dialog.features.contains(.hasTitleBar))
        // A modal window without attributes has a title bar but no boxes.
        #expect(dialog.region(.closeBox).isEmpty)
        #expect(dialog.hitTest(Point(v: 25, h: 100)) == .drag)
    }

    @Test func regions() throws {
        let manager = makeManager()
        let window = try manager.newWindow(attributes: .standardDocument,
                                           bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        #expect(window.region(.structure) == Region(rect: Rect(top: 20, left: 36, bottom: 144, right: 144)))
        #expect(window.region(.content) == Region(rect: Rect(top: 40, left: 40, bottom: 140, right: 140)))
        #expect(window.region(.titleBar) == Region(rect: Rect(top: 20, left: 36, bottom: 40, right: 144)))
        // The boxes: 11 pixels square, four from an edge, set to the bar's
        // middle.
        #expect(window.region(.closeBox) == Region(rect: Rect(top: 24, left: 40, bottom: 35, right: 51)))
        #expect(window.region(.zoomBox) == Region(rect: Rect(top: 24, left: 129, bottom: 35, right: 140)))
        #expect(window.region(.collapseBox) == Region(rect: Rect(top: 24, left: 114, bottom: 35, right: 125)))
        #expect(window.region(.grow) == Region(rect: Rect(top: 125, left: 125, bottom: 140, right: 140)))
        #expect(window.region(.titleText) == Region(rect: Rect(top: 20, left: 55, bottom: 40, right: 110)))
        // The drag region is the title bar without its boxes.
        #expect(window.region(.drag) == Region(rect: Rect(top: 20, left: 36, bottom: 40, right: 144))
            .subtracting(Region(rect: Rect(top: 24, left: 40, bottom: 35, right: 51)))
            .subtracting(Region(rect: Rect(top: 24, left: 129, bottom: 35, right: 140)))
            .subtracting(Region(rect: Rect(top: 24, left: 114, bottom: 35, right: 125))))
        // A window that can't grow has no grow region.
        let fixed = try manager.newWindow(attributes: [.closeBox], bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        #expect(fixed.region(.grow).isEmpty)
    }

    @Test func hitTesting() throws {
        let manager = makeManager()
        let window = try manager.newWindow(attributes: .standardDocument,
                                           bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        window.show()
        #expect(window.hitTest(Point(v: 100, h: 100)) == .content)
        #expect(window.hitTest(Point(v: 25, h: 80)) == .drag)
        #expect(window.hitTest(Point(v: 30, h: 44)) == .goAway)
        #expect(window.hitTest(Point(v: 30, h: 132)) == .zoomIn)
        #expect(window.hitTest(Point(v: 30, h: 118)) == .collapseBox)
        #expect(window.hitTest(Point(v: 135, h: 135)) == .grow)
        #expect(window.hitTest(Point(v: 10, h: 10)) == nil)
        // The zoom box answers by the window's state; zoomed to the whole
        // desktop, its structure moved with it.
        window.zoom()
        #expect(window.hitTest(Point(v: 30, h: 630)) == .zoomOut)
        #expect(window.hitTest(Point(v: 30, h: 132)) == .drag)
        // A window that can't grow takes the click as content.
        let fixed = try manager.newWindow(attributes: [], bounds: Rect(top: 200, left: 200, bottom: 300, right: 300))
        fixed.show()
        #expect(fixed.hitTest(Point(v: 295, h: 295)) == .content)
        // The window's frame, out of its parts.
        let framed = try manager.newWindow(windowClass: .plain, bounds: Rect(top: 400, left: 400, bottom: 440, right: 440))
        framed.show()
        #expect(framed.hitTest(Point(v: 399, h: 401)) == .structure)
    }

    @Test func titles() throws {
        let manager = makeManager()
        let window = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140), title: "Zürich")
        window.title = "Genève"
        #expect(window.title == "Genève")
    }

    @Test func zooming() throws {
        let manager = makeManager()
        let window = try manager.newWindow(attributes: .standardDocument,
                                           bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        #expect(!window.isInStandardState)
        // The standard state: the desktop, minus the frame.
        window.zoom()
        #expect(window.isInStandardState)
        #expect(window.contentBounds == Rect(top: 40, left: 4, bottom: 476, right: 636))
        #expect(window.userState == Rect(top: 40, left: 40, bottom: 140, right: 140))
        // Back to the user state, which the window keeps.
        window.zoom()
        #expect(!window.isInStandardState)
        #expect(window.contentBounds == Rect(top: 40, left: 40, bottom: 140, right: 140))
        // The states the program sets, as SetWindowUserState and
        // SetWindowStandardState. The user state is set in the standard
        // state, which ZoomWindow returns to; ZoomWindow saves the state
        // it leaves, so one set while the window sits in it is saved over,
        // as the classic's does.
        window.zoom()
        window.setUserState(Rect(top: 60, left: 60, bottom: 120, right: 120))
        window.zoom()
        #expect(window.contentBounds == Rect(top: 60, left: 60, bottom: 120, right: 120))
        window.setStandardState(Rect(top: 80, left: 80, bottom: 180, right: 180))
        window.zoom()
        #expect(window.contentBounds == Rect(top: 80, left: 80, bottom: 180, right: 180))
        window.zoom()
        #expect(window.contentBounds == Rect(top: 60, left: 60, bottom: 120, right: 120))
        // A window without a zoom attribute never zooms.
        let fixed = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        fixed.zoom()
        #expect(fixed.contentBounds == Rect(top: 40, left: 40, bottom: 140, right: 140))
    }

    @Test func collapsing() throws {
        let manager = makeManager()
        let window = try manager.newWindow(attributes: .standardDocument,
                                           bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        window.show()
        window.collapse()
        // Collapsed: the structure is the title bar alone.
        #expect(window.structureBounds == Rect(top: 20, left: 36, bottom: 40, right: 144))
        #expect(window.contentBounds == .zero)
        #expect(window.contentRegion.isEmpty)
        #expect(window.visibleRegion.isEmpty)
        // The port's bounds are where they were: kWindowGlobalPortRgn
        // isn't affected by collapsing.
        #expect(window.region(.globalPort) == Region(rect: Rect(top: 40, left: 40, bottom: 140, right: 140)))
        #expect(window.region(.zoomBox).isEmpty)
        #expect(!window.region(.closeBox).isEmpty)
        window.expand()
        #expect(window.structureBounds == Rect(top: 20, left: 36, bottom: 144, right: 144))
        #expect(window.visibleRegion == window.contentRegion)
        // Expanding shows everything again.
        #expect(window.updateRegion == window.contentRegion)
        // A window without a title bar can't collapse.
        let simple = try manager.newWindow(windowClass: .simple, bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        simple.collapse()
        #expect(simple.contentBounds == simple.structureBounds)
    }

    @Test func bounds() throws {
        let manager = makeManager()
        let window = try manager.newWindow(attributes: .standardDocument,
                                           bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        // MoveWindow places the content; MoveWindowStructure the structure.
        window.move(h: 200, v: 220)
        #expect(window.contentBounds == Rect(top: 220, left: 200, bottom: 320, right: 300))
        #expect(window.structureBounds == Rect(top: 200, left: 196, bottom: 324, right: 304))
        window.moveStructure(h: 10, v: 30)
        #expect(window.structureBounds == Rect(top: 30, left: 10, bottom: 154, right: 118))
        #expect(window.contentBounds == Rect(top: 50, left: 14, bottom: 150, right: 114))
        // SizeWindow sizes the content, from its top left.
        window.size(width: 120, height: 80)
        #expect(window.contentBounds == Rect(top: 50, left: 14, bottom: 130, right: 134))
        // SetWindowBounds with either region; the other follows.
        try window.setBounds(Rect(top: 100, left: 100, bottom: 140, right: 140), region: .structure)
        #expect(window.contentBounds == Rect(top: 120, left: 104, bottom: 136, right: 136))
        try window.setBounds(Rect(top: 40, left: 40, bottom: 100, right: 100), region: .content)
        #expect(window.structureBounds == Rect(top: 20, left: 36, bottom: 104, right: 104))
        #expect(throws: MacError.parameter) {
            try window.setBounds(.zero, region: .titleBar)
        }
        #expect(throws: MacError.parameter) {
            _ = try window.bounds(of: .titleBar)
        }
        #expect(try window.bounds(of: .structure) == window.structureBounds)
        #expect(try window.bounds(of: .content) == window.contentBounds)
    }

    @Test func resizing() throws {
        let manager = makeManager()
        let window = try manager.newWindow(attributes: .standardDocument,
                                           bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        window.show()
        window.port.perform(.paint, rect: Rect(top: 10, left: 10, bottom: 11, right: 11))
        #expect(window.pixels.color(at: Point(v: 10, h: 10)) == .black)
        window.size(width: 120, height: 80)
        // The buffer starts over: a resized window draws itself again.
        #expect(window.port.portRect == Rect(top: 0, left: 0, bottom: 80, right: 120))
        #expect(window.pixels.color(at: Point(v: 10, h: 10)) == .white)
        #expect(window.updateRegion == window.contentRegion)
    }

    @Test func changingAttributes() throws {
        let manager = makeManager()
        let window = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        #expect(window.region(.closeBox).isEmpty)
        window.changeAttributes(add: .closeBox)
        #expect(!window.region(.closeBox).isEmpty)
        window.changeAttributes(add: .resizable)
        #expect(!window.region(.grow).isEmpty)
        window.changeAttributes(remove: .resizable)
        #expect(window.region(.grow).isEmpty)
    }

    @Test func portAndCoordinates() throws {
        let manager = makeManager()
        let window = try manager.newWindow(attributes: .standardDocument,
                                           bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        window.show()
        #expect(manager.window(withPort: window.port) === window)
        #expect(window.device === manager.quickDraw.mainDevice)
        #expect(window.localToGlobal(.zero) == Point(v: 40, h: 40))
        #expect(window.globalToLocal(Point(v: 40, h: 40)) == .zero)
        // The port's local bounds are the content's, and drawing in the
        // port lands in the window's buffer.
        window.port.perform(.paint, rect: Rect(top: 0, left: 0, bottom: 1, right: 1))
        #expect(window.pixels.color(at: Point(v: 0, h: 0)) == .black)
    }

    @Test func parentAndReference() throws {
        let manager = makeManager()
        let parent = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        let sheet = try manager.newWindow(windowClass: .sheet, bounds: Rect(top: 60, left: 60, bottom: 120, right: 120))
        sheet.parent = parent
        #expect(sheet.parent === parent)
        sheet.referenceConstant = 42
        #expect(sheet.referenceConstant == 42)
        sheet.kindCode = 2
        #expect(sheet.kindCode == 2)
    }
}
