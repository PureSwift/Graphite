import Testing
import Foundation
import CacaoHost
import GraphiteBase
import GraphiteDialogs
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
