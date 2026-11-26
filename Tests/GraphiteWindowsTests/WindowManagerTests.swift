import Testing
import GraphiteBase
import GraphiteQuickDraw
import GraphiteWindows

@Suite struct WindowManagerTests {

    /// Windows by identity, in their order.
    private func listed(_ windows: [Window]) -> [ObjectIdentifier] {
        windows.map(ObjectIdentifier.init)
    }

    private func makeManager() -> WindowManager {
        WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    }

    @Test func ordering() throws {
        let manager = makeManager()
        let first = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        let second = try manager.newWindow(bounds: Rect(top: 60, left: 60, bottom: 160, right: 160))
        // A new window comes up in front of its layer.
        #expect(listed(manager.windows) == listed([second, first]))
        first.show()
        second.show()
        #expect(manager.frontWindow === second)
        first.bringToFront()
        #expect(manager.frontWindow === first)
        #expect(listed(manager.windows) == listed([first, second]))
        first.sendBehind(second)
        #expect(listed(manager.windows) == listed([second, first]))
        // Hidden windows keep their place in the list.
        second.hide()
        #expect(manager.frontWindow === first)
        second.show()
        #expect(manager.frontWindow === second)
    }

    @Test func layers() throws {
        let manager = makeManager()
        let document = try manager.newWindow(attributes: .standardDocument,
                                             bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        document.show()
        let palette = try manager.newWindow(windowClass: .floating, attributes: .standardFloating,
                                            bounds: Rect(top: 30, left: 30, bottom: 90, right: 150))
        palette.show()
        // A palette floats above the documents, however they are ordered.
        #expect(listed(manager.windows) == listed([palette, document]))
        document.bringToFront()
        #expect(listed(manager.windows) == listed([palette, document]))
        // FrontWindow skips the palettes.
        #expect(manager.frontWindow === document)
        #expect(manager.frontFloatingWindow === palette)
        let alert = try manager.newWindow(windowClass: .alert, bounds: Rect(top: 100, left: 100, bottom: 180, right: 200))
        alert.show()
        #expect(listed(manager.windows) == listed([alert, palette, document]))
    }

    @Test func activation() throws {
        let manager = makeManager()
        let first = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        first.show()
        #expect(first.isActive && manager.activeWindow === first)
        let second = try manager.newWindow(bounds: Rect(top: 60, left: 60, bottom: 160, right: 160))
        second.show()
        #expect(second.isActive && !first.isActive)
        first.select()
        #expect(first.isActive && !second.isActive)
        // Hiding the active window activates the one behind it.
        first.hide()
        #expect(manager.activeWindow === second && second.isActive)
        // Selecting a hidden window shows it.
        first.select()
        #expect(first.isVisible && first.isActive)
        // The palettes are active independently of the documents.
        let palette = try manager.newWindow(windowClass: .floating, bounds: Rect(top: 30, left: 30, bottom: 90, right: 150))
        palette.show()
        #expect(manager.activeFloatingWindow === palette && palette.isActive)
        #expect(manager.activeWindow === first)
        palette.hide()
        #expect(manager.activeFloatingWindow == nil)
        first.activate(false)
        #expect(!first.isActive && manager.activeWindow == nil)
    }

    @Test func withoutActivates() throws {
        let manager = makeManager()
        let quiet = try manager.newWindow(attributes: .noActivates, bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        quiet.show()
        #expect(manager.activeWindow == nil && !quiet.isActive)
        let loud = try manager.newWindow(bounds: Rect(top: 60, left: 60, bottom: 160, right: 160))
        loud.show()
        #expect(manager.activeWindow === loud)
    }

    @Test func finding() throws {
        let manager = makeManager()
        let back = try manager.newWindow(attributes: .standardDocument,
                                         bounds: Rect(top: 40, left: 40, bottom: 340, right: 340))
        back.show()
        let front = try manager.newWindow(attributes: .standardDocument,
                                          bounds: Rect(top: 100, left: 100, bottom: 200, right: 200))
        front.show()
        let (contentPart, contentWindow) = manager.findWindow(at: Point(v: 120, h: 120))
        #expect(contentPart == .content && contentWindow === front)
        // The front window's frame, and the window behind it.
        let (framePart, frameWindow) = manager.findWindow(at: Point(v: 25, h: 60))
        #expect(framePart == .drag && frameWindow === back)
        let (deskPart, deskWindow) = manager.findWindow(at: Point(v: 450, h: 400))
        #expect(deskPart == .desk && deskWindow == nil)
        let (barPart, barWindow) = manager.findWindow(at: Point(v: 10, h: 100))
        #expect(barPart == .menuBar && barWindow == nil)
    }

    @Test func clicksPassingThrough() throws {
        let manager = makeManager()
        let back = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 340, right: 340))
        back.show()
        let front = try manager.newWindow(attributes: .ignoreClicks,
                                          bounds: Rect(top: 100, left: 100, bottom: 200, right: 200))
        front.show()
        let (part, window) = manager.findWindow(at: Point(v: 120, h: 120))
        #expect(part == .content && window === back)
        front.changeAttributes(add: .opaqueForEvents, remove: .ignoreClicks)
        let (through, windowBehind) = manager.findWindow(at: Point(v: 120, h: 120))
        #expect(through == .content && windowBehind === back)
    }

    @Test func desktop() throws {
        let manager = makeManager()
        #expect(manager.desktopRegion == Region(rect: Rect(top: 20, left: 0, bottom: 480, right: 640)))
        let window = try manager.newWindow(bounds: Rect(top: 0, left: 0, bottom: 100, right: 100))
        window.show()
        // The menu bar is nobody's to draw over.
        #expect(window.visibleRegion == Region(rect: Rect(top: 20, left: 0, bottom: 100, right: 100)))
        // Nor is anything past the edge of a screen.
        let edge = try manager.newWindow(bounds: Rect(top: 400, left: 600, bottom: 500, right: 700))
        edge.show()
        #expect(edge.visibleRegion == Region(rect: Rect(top: 400, left: 600, bottom: 480, right: 640)))
    }

    @Test func centering() throws {
        let manager = makeManager()
        let window = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 120, right: 140))
        // The structure — content, title bar and frame — is what centers.
        #expect(window.structureBounds.width == 108 && window.structureBounds.height == 104)
        try manager.reposition(window, method: .centerOnMainScreen)
        #expect(window.structureBounds == Rect(top: 198, left: 266, bottom: 302, right: 374))
        let parent = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        try manager.reposition(window, method: .centerOnParentWindow, relativeTo: parent)
        #expect(window.structureBounds == Rect(top: 30, left: 36, bottom: 134, right: 144))
        #expect(throws: MacError.parameter) {
            try manager.reposition(window, method: .centerOnParentWindow)
        }
    }

    @Test func cascading() throws {
        let manager = makeManager()
        // The first window at the desktop's corner, the rest a title bar's
        // worth below and to the right.
        let first = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 120, right: 140))
        try manager.reposition(first, method: .cascadeOnMainScreen)
        #expect(first.structureBounds == Rect(top: 20, left: 0, bottom: 124, right: 108))
        let second = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 120, right: 140))
        try manager.reposition(second, method: .cascadeOnMainScreen)
        #expect(second.structureBounds == Rect(top: 40, left: 20, bottom: 144, right: 128))
        // From the corner again when the next wouldn't fit.
        manager.cascadeOrigin = Point(v: 400, h: 500)
        let third = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 120, right: 140))
        try manager.reposition(third, method: .cascadeOnMainScreen)
        #expect(third.structureBounds == Rect(top: 400, left: 500, bottom: 504, right: 608))
        #expect(manager.cascadeOrigin == Point(v: 20, h: 0))
        // By a parent window: below and to the right of it.
        let parent = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        let sheet = try manager.newWindow(windowClass: .sheet, bounds: Rect(top: 60, left: 60, bottom: 120, right: 120))
        try manager.reposition(sheet, method: .cascadeOnParentWindow, relativeTo: parent)
        #expect(sheet.structureBounds == Rect(top: 40, left: 56, bottom: 100, right: 116))
        #expect(throws: MacError.parameter) {
            try manager.reposition(sheet, method: .cascadeOnParentWindow)
        }
    }

    @Test func alertPosition() throws {
        let manager = makeManager()
        let alert = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 120, right: 140))
        try manager.reposition(alert, method: .alertPositionOnMainScreen)
        // Centered across, three eighths of the way down the desktop.
        #expect(alert.structureBounds == Rect(top: 140, left: 266, bottom: 244, right: 374))
    }

    @Test func lettingGo() throws {
        let manager = makeManager()
        // A window the program lets go of is gone from the list.
        try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        #expect(manager.windows.isEmpty)
        let kept = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        #expect(listed(manager.windows) == listed([kept]))
        kept.dispose()
        #expect(manager.windows.isEmpty && !kept.isVisible)
    }
}
