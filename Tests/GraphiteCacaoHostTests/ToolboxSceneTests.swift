import Testing
import Foundation
import CacaoHost
import CacaoRender
import GraphiteBase
import GraphiteDialogs
import GraphiteControls
import GraphiteCacaoRenderer
import GraphiteEvents
import GraphiteQuickDraw
import GraphiteWindows
@testable import GraphiteCacaoHost

@MainActor
@Test func dialogInputAndRendering() throws {
    let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 50, bottom: 150, right: 250), items: [
        DialogItem(bounds: Rect(top: 10, left: 10, bottom: 30, right: 100), kind: .editText),
        DialogItem(bounds: Rect(top: 40, left: 10, bottom: 60, right: 80), kind: .button, text: "OK")
    ])
    dialog.defaultItem = 2
    try dialog.attach(to: manager)
    var hits: [Int] = []
    let scene = try #require(ToolboxScene(dialog: dialog, onItemHit: { hits.append($0) }))
    scene.handle(.text("Hello"), time: 0)
    #expect(dialog.text(of: 1)?.bytes == Array("Hello".utf8))
    scene.handle(.pointer(.began, button: .primary, at: CGPoint(x: 20, y: 50), isFromTouch: false), time: 0)
    scene.handle(.pointer(.ended, button: .primary, at: CGPoint(x: 20, y: 50), isFromTouch: false), time: 0)
    #expect(hits == [2])
    #expect(!scene.displayList().items.isEmpty)
}

@MainActor
@Test func hostInputEntersSharedQueue() throws {
    let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 70, bottom: 150, right: 270))
    try dialog.attach(to: manager)
    let scene = try #require(ToolboxScene(dialog: dialog, onItemHit: { _ in }))
    let queue = EventQueue()
    scene.eventQueue = queue
    scene.handle(.text("Hi"), time: 1)
    let event = try #require(queue.receive())
    #expect(event.type == EventType(eventClass: "text", kind: 1))
    #expect(event.parameter("text", type: "TEXT")?.bytes == [72, 105])
    scene.handle(.pointer(.began, button: .primary, at: CGPoint(x: 10, y: 20), isFromTouch: false), time: 2)
    let pointer = try #require(queue.receive())
    #expect(pointer.type == EventType(eventClass: "mous", kind: 1))
    var point = BigEndianWriter()
    point.write(Float(80).bitPattern); point.write(Float(70).bitPattern)
    #expect(pointer.parameter("mloc", type: "hipt")?.bytes == point.bytes)
}

@MainActor
@Test func rendererShowsCheckBoxState() throws {
    let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    let window = try manager.newWindow(bounds: Rect(top: 50, left: 50, bottom: 150, right: 250))
    let control = Control(kind: .checkBox, bounds: Rect(top: 10, left: 10, bottom: 30, right: 100), title: "Option")
    control.maximum = 1
    let renderer = ToolboxRenderer()
    let unchecked = renderer.render(window: window, controls: [control])
    control.value = 1
    let checked = renderer.render(window: window, controls: [control])
    #expect(checked.items.count > unchecked.items.count)
    control.hide()
    #expect(renderer.render(window: window, controls: [control]).items.count == 1)
}

@MainActor
@Test func dispatcherRoutesHostInput() throws {
    let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 70, bottom: 150, right: 270), items: [
        DialogItem(bounds: Rect(top: 10, left: 10, bottom: 30, right: 100), kind: .editText),
        DialogItem(bounds: Rect(top: 40, left: 10, bottom: 60, right: 80), kind: .button, text: "OK")
    ])
    try dialog.attach(to: manager)
    var hits: [Int] = []
    let scene = try #require(ToolboxScene(dialog: dialog, onItemHit: { _ in }))
    let dispatcher = ToolboxEventDispatcher(windows: manager, itemHit: { _, item in hits.append(item) })
    dispatcher.attach(scene)
    scene.handle(.text("Hi"), time: 1)
    #expect(dialog.text(of: 1)?.bytes == [72, 105])
    scene.handle(.pointer(.began, button: .primary, at: CGPoint(x: 20, y: 50), isFromTouch: false), time: 2)
    scene.handle(.pointer(.ended, button: .primary, at: CGPoint(x: 20, y: 50), isFromTouch: false), time: 3)
    #expect(hits == [2])
    #expect(dispatcher.queue.count == 0)
}

@MainActor
@Test func hostFrameUpdatesWindowSize() throws {
    let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 70, bottom: 150, right: 270))
    try dialog.attach(to: manager)
    let scene = try #require(ToolboxScene(dialog: dialog, onItemHit: { _ in }))
    #expect(scene.update(HostFrame(time: 0, size: CGSize(width: 220, height: 120), scale: 1)))
    #expect(scene.window.contentBounds.width == 220)
    #expect(scene.window.contentBounds.height == 120)
    #expect(!scene.update(HostFrame(time: 1, size: CGSize(width: 220, height: 120), scale: 1)))
}

@MainActor
@Test func cancellingPointerDoesNotSelectControl() throws {
    let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 70, bottom: 150, right: 270), items: [
        DialogItem(bounds: Rect(top: 10, left: 10, bottom: 30, right: 80), kind: .button, text: "OK")
    ])
    try dialog.attach(to: manager)
    var hits: [Int] = []
    let scene = try #require(ToolboxScene(dialog: dialog, onItemHit: { _ in }))
    let dispatcher = ToolboxEventDispatcher(windows: manager, itemHit: { _, item in hits.append(item) })
    dispatcher.attach(scene)
    let point = CGPoint(x: 20, y: 20)
    scene.handle(.pointer(.began, button: .primary, at: point, isFromTouch: false), time: 1)
    scene.handle(.pointer(.cancelled, button: .primary, at: point, isFromTouch: false), time: 2)
    scene.handle(.pointer(.ended, button: .primary, at: point, isFromTouch: false), time: 3)
    #expect(hits.isEmpty)
}

@MainActor
@Test func rendererMarksDefaultButton() throws {
    let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 50, bottom: 150, right: 250), items: [
        DialogItem(bounds: Rect(top: 40, left: 10, bottom: 60, right: 80), kind: .button, text: "OK")
    ])
    try dialog.attach(to: manager)
    let window = try #require(dialog.window)
    let renderer = ToolboxRenderer()
    let plain = renderer.render(window: window, dialog: dialog)
    dialog.defaultItem = 1
    let marked = renderer.render(window: window, dialog: dialog)
    #expect(marked.items.count == plain.items.count + 2)
}

@MainActor
@Test func rendererPlacesContentInsideWindowFrame() throws {
    let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    let window = try manager.newWindow(bounds: Rect(top: 50, left: 70, bottom: 150, right: 270), title: "Document")
    let list = ToolboxRenderer().renderFrame(window: window)
    let last = try #require(list.items.last)
    #expect(last.frame.minX == CGFloat(Int(window.contentBounds.left) - Int(window.structureBounds.left)))
    #expect(last.frame.minY == CGFloat(Int(window.contentBounds.top) - Int(window.structureBounds.top)))
    #expect(list.items.count >= 3)
}

@MainActor
@Test func framedSceneOffsetsPointerInput() throws {
    let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 70, bottom: 150, right: 270), items: [
        DialogItem(bounds: Rect(top: 10, left: 10, bottom: 30, right: 80), kind: .button, text: "OK")
    ])
    try dialog.attach(to: manager)
    var hits: [Int] = []
    let scene = try #require(ToolboxScene(dialog: dialog, onItemHit: { hits.append($0) }))
    scene.drawsWindowFrame = true
    let bounds = scene.window.contentBounds
    let structure = scene.window.structureBounds
    let point = CGPoint(x: 20 + Int(bounds.left) - Int(structure.left), y: 20 + Int(bounds.top) - Int(structure.top))
    scene.handle(.pointer(.began, button: .primary, at: point, isFromTouch: false), time: 1)
    scene.handle(.pointer(.ended, button: .primary, at: point, isFromTouch: false), time: 2)
    #expect(hits == [1])
    #expect(scene.hitTest(at: CGPoint(x: 30, y: 3)) == .draggable)
}

@MainActor
@Test func framedSceneSizePreservesContentDimensions() throws {
    let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 70, bottom: 150, right: 270))
    try dialog.attach(to: manager)
    let scene = try #require(ToolboxScene(dialog: dialog, onItemHit: { _ in }))
    scene.drawsWindowFrame = true
    let structure = scene.window.structureBounds
    #expect(scene.update(HostFrame(time: 0, size: CGSize(width: structure.width, height: structure.height), scale: 1)))
    #expect(scene.window.contentBounds.width == 200)
    #expect(scene.window.contentBounds.height == 100)
}

@MainActor
@Test func oversizedHostFrameDoesNotOverflowWindowCoordinates() throws {
    let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 70, bottom: 150, right: 270))
    try dialog.attach(to: manager)
    let scene = try #require(ToolboxScene(dialog: dialog, onItemHit: { _ in }))
    _ = scene.update(HostFrame(time: 0, size: CGSize(width: 200, height: 100), scale: 1))
    #expect(!scene.update(HostFrame(time: 1, size: CGSize(width: 32767, height: 100), scale: 1)))
    #expect(scene.window.contentBounds.width == 200)
}

@MainActor
@Test func rendererMarksFocusedTextItem() throws {
    let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 50, bottom: 150, right: 250), items: [
        DialogItem(bounds: Rect(top: 10, left: 10, bottom: 30, right: 100), kind: .editText),
        DialogItem(bounds: Rect(top: 40, left: 10, bottom: 60, right: 100), kind: .editText)
    ])
    try dialog.attach(to: manager)
    let window = try #require(dialog.window)
    let first = ToolboxRenderer().render(window: window, dialog: dialog)
    dialog.focusTextItem(2)
    let second = ToolboxRenderer().render(window: window, dialog: dialog)
    #expect(first.items.map(\.frame) != second.items.map(\.frame))
}

@MainActor
private struct TestTextMeasurement: TextMeasurementService {
    func measure(_ text: ResolvedText, in proposal: ProposedViewSize) -> TextMeasurement {
        let count = text.string.unicodeScalars.count
        return TextMeasurement(lines: [.init(frame: CGRect(x: 0, y: 0, width: count * 5, height: 10), baseline: 8,
                                             boundaries: (0...count).map { .init(offset: $0, x: CGFloat($0 * 5)) })])
    }
}

@MainActor
@Test func rendererUsesMeasuredCaretAndSelection() throws {
    let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 50, bottom: 150, right: 250), items: [
        DialogItem(bounds: Rect(top: 10, left: 10, bottom: 30, right: 100), kind: .editText, text: "abc")
    ])
    try dialog.attach(to: manager)
    let window = try #require(dialog.window)
    let renderer = ToolboxRenderer(textMeasurement: TestTextMeasurement())
    dialog.selectText(of: 1, range: 2..<2)
    let caret = renderer.render(window: window, dialog: dialog)
    #expect(caret.items.contains { $0.frame == CGRect(x: 20, y: 10, width: 1, height: 10) })
    dialog.selectText(of: 1, range: 0..<2)
    let selection = renderer.render(window: window, dialog: dialog)
    #expect(selection.items.contains { $0.frame == CGRect(x: 10, y: 10, width: 10, height: 10) })
}
