import Testing
import Foundation
import Foundation
import CacaoHost
import GraphiteBase
import GraphiteDialogs
import GraphiteQuickDraw
import GraphiteWindows
import GraphiteCacaoHost

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["GRAPHITE_WINDOW_TEST"] == "1", "Requires an interactive display")) func hostWindowOpensAndCloses() throws {
    let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 640, height: 480)]))
    let dialog = Dialog(kind: .modeless, bounds: Rect(top: 50, left: 70, bottom: 150, right: 270))
    try dialog.attach(to: manager)
    var detached = false
    let scene = try #require(ToolboxScene(dialog: dialog, onItemHit: { _ in }, onDetach: { detached = true }))
    let dispatcher = ToolboxEventDispatcher(windows: manager, itemHit: { _, _ in })
    var opened = false
    HostRuntime.run {
        guard let host = ToolboxWindowHost.present(scene, dispatcher: dispatcher) else { return }
        opened = true
        HostRuntime.close(host)
    }
    #expect(opened)
    #expect(detached)
    #expect(!dialog.isVisible)
    #expect(scene.eventQueue == nil)
}
