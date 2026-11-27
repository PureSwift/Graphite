import Testing
import Foundation
import CacaoHost
import GraphiteBase
import GraphiteDialogs
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
