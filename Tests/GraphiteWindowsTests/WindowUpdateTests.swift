import Testing
import GraphiteBase
import GraphiteQuickDraw
import GraphiteWindows

@Suite struct WindowUpdateTests {

    private func makeManager() -> WindowManager {
        WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    }

    /// Records what the host is told to flush.
    private final class Flushed {
        var regions: [Region] = []
    }

    @Test func shownNeedsDrawing() throws {
        let manager = makeManager()
        let window = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        #expect(!window.needsUpdate)
        // A window just shown has everything to draw: all it can be seen.
        window.show()
        #expect(window.updateRegion == window.contentRegion)
        window.hide()
        window.show()
        #expect(window.updateRegion == window.contentRegion)
        // Hidden, nothing is asked of it.
        window.hide()
        #expect(window.visibleRegion.isEmpty)
    }

    @Test func invalidating() throws {
        let manager = makeManager()
        let window = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        window.show()
        window.validate(window.contentBounds)
        #expect(!window.needsUpdate)
        window.invalidate(Rect(top: 60, left: 60, bottom: 70, right: 70))
        #expect(window.updateRegion == Region(rect: Rect(top: 60, left: 60, bottom: 70, right: 70)))
        window.invalidate(Region(rect: Rect(top: 80, left: 80, bottom: 90, right: 90)))
        #expect(window.updateRegion == Region(rect: Rect(top: 60, left: 60, bottom: 70, right: 70))
            .union(Region(rect: Rect(top: 80, left: 80, bottom: 90, right: 90))))
        window.validate(Rect(top: 60, left: 60, bottom: 70, right: 70))
        #expect(window.updateRegion == Region(rect: Rect(top: 80, left: 80, bottom: 90, right: 90)))
        window.validate(window.contentRegion)
        #expect(!window.needsUpdate)
    }

    @Test func withoutUpdates() throws {
        let manager = makeManager()
        let window = try manager.newWindow(attributes: .noUpdates, bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        window.show()
        // A window with kWindowNoUpdatesAttribute is never asked to
        // draw anything: it draws when it likes.
        #expect(window.updateRegion.isEmpty && !window.needsUpdate)
        window.invalidate(Rect(top: 60, left: 60, bottom: 70, right: 70))
        #expect(window.updateRegion.isEmpty)
    }

    @Test func beginAndEndUpdate() throws {
        let manager = makeManager()
        let window = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        window.show()
        window.validate(window.contentBounds)
        window.invalidate(Rect(top: 60, left: 60, bottom: 70, right: 70))
        window.beginUpdate()
        // Drawing is held to the update region, in the port's local
        // coordinates, and the update region is spent.
        #expect(window.updateRegion.isEmpty)
        let clip = Region(rect: Rect(top: 20, left: 20, bottom: 30, right: 30))
        #expect(window.port.clipRegion == clip)
        #expect(window.port.visibleRegion == clip)
        window.port.perform(.paint, rect: Rect(top: 0, left: 0, bottom: 100, right: 100))
        #expect(window.pixels.color(at: Point(v: 25, h: 25)) == .black)
        #expect(window.pixels.color(at: Point(v: 50, h: 50)) == .white)
        window.endUpdate()
        #expect(window.port.visibleRegion == Region(rect: window.port.portRect))
        #expect(!window.needsUpdate)
        // EndUpdate without BeginUpdate does nothing.
        window.endUpdate()
        #expect(window.port.visibleRegion == Region(rect: window.port.portRect))
    }

    @Test func occlusion() throws {
        let manager = makeManager()
        let behind = try manager.newWindow(attributes: .standardDocument,
                                           bounds: Rect(top: 40, left: 40, bottom: 340, right: 340))
        behind.show()
        let front = try manager.newWindow(attributes: .standardDocument,
                                          bounds: Rect(top: 100, left: 100, bottom: 200, right: 200))
        front.show()
        // The window behind sees everything but what the front one's
        // structure covers.
        let frontStructure = Region(rect: Rect(top: 80, left: 96, bottom: 204, right: 204))
        let behindContent = Region(rect: Rect(top: 40, left: 40, bottom: 340, right: 340))
        #expect(behind.visibleRegion == behindContent.subtracting(frontStructure))
        #expect(front.visibleRegion == Region(rect: Rect(top: 100, left: 100, bottom: 200, right: 200)))
        behind.validate(behind.contentRegion)
        #expect(!behind.needsUpdate)
        // The front window gone, what it covered is seen — and so drawn —
        // again.
        front.hide()
        #expect(behind.visibleRegion == behindContent)
        #expect(behind.updateRegion == frontStructure)
        front.show()
        #expect(behind.visibleRegion == behindContent.subtracting(frontStructure))
        // What was covered again stays drawn: the buffer keeps it.
        #expect(behind.updateRegion == frontStructure)
    }

    @Test func uncoveringByMove() throws {
        let manager = makeManager()
        let behind = try manager.newWindow(attributes: .standardDocument,
                                           bounds: Rect(top: 40, left: 40, bottom: 340, right: 340))
        behind.show()
        let front = try manager.newWindow(attributes: .standardDocument,
                                          bounds: Rect(top: 100, left: 100, bottom: 200, right: 200))
        front.show()
        behind.validate(behind.contentRegion)
        front.move(h: 300, v: 300)
        // The front window still covers a corner of the one behind; the
        // part it let go of needs drawing.
        let stillCovered = Region(rect: Rect(top: 280, left: 296, bottom: 340, right: 340))
        let letGo = Region(rect: Rect(top: 80, left: 96, bottom: 204, right: 204))
        #expect(behind.visibleRegion == Region(rect: Rect(top: 40, left: 40, bottom: 340, right: 340))
            .subtracting(stillCovered))
        #expect(behind.updateRegion == letGo)
        #expect(behind.updateRegion.contains(Point(v: 100, h: 100)))
        #expect(!behind.updateRegion.contains(Point(v: 300, h: 310)))
        #expect(!behind.updateRegion.contains(Point(v: 60, h: 50)))
    }

    @Test func flushing() throws {
        let manager = makeManager()
        let window = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        window.show()
        let flushed = Flushed()
        manager.flushObserver = { _, region in
            flushed.regions.append(region)
        }
        window.flush()
        #expect(flushed.regions == [window.contentRegion])
        let part = Region(rect: Rect(top: 50, left: 50, bottom: 60, right: 60))
        window.flush(part)
        #expect(flushed.regions == [window.contentRegion, part])
        // Without a host to flush to, the buffer stays as it was.
        manager.flushObserver = nil
        window.flush()
        #expect(window.pixels.color(at: Point(v: 50, h: 50)) == .white)
    }

    @Test func portBits() throws {
        let manager = makeManager()
        let window = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        #expect(!window.arePortBitsLocked)
        window.lockPortBits()
        #expect(window.arePortBitsLocked)
        window.lockPortBits()
        window.unlockPortBits()
        #expect(window.arePortBitsLocked)
        window.unlockPortBits()
        #expect(!window.arePortBitsLocked)
        window.unlockPortBits()
        #expect(!window.arePortBitsLocked)
    }

    @Test func drawingThroughThePort() throws {
        let manager = makeManager()
        let window = try manager.newWindow(bounds: Rect(top: 40, left: 40, bottom: 140, right: 140))
        window.show()
        // Drawing in the port lands in the window's buffer, held to what
        // can be seen.
        window.port.perform(.paint, rect: Rect(top: -20, left: -20, bottom: 120, right: 120))
        #expect(window.pixels.color(at: Point(v: 0, h: 0)) == .black)
        #expect(window.pixels.color(at: Point(v: 99, h: 99)) == .black)
        // The flush carries it to the host as the whole content.
        let flushed = Flushed()
        manager.flushObserver = { _, region in
            flushed.regions.append(region)
        }
        window.flush()
        #expect(flushed.regions == [window.contentRegion])
    }
}
