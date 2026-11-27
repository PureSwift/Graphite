import Foundation
import CacaoHost
import GraphiteBase

/// Presents a Graphite dialog scene in a CacaoHost window with system chrome.
@MainActor
public enum ToolboxWindowHost {
    /// Call while `HostRuntime` is running. Returns nil if Cacao cannot
    /// create a window, leaving the scene and dispatcher unchanged.
    @discardableResult
    public static func present(_ scene: ToolboxScene, dispatcher: ToolboxEventDispatcher, graphiteFrame: Bool = false) -> HostWindow? {
        let bounds = graphiteFrame ? scene.window.structureBounds : scene.window.contentBounds
        guard let host = HostRuntime.openWindow(title: MacRoman.decode(scene.dialog.title.bytes),
                                                 size: CGSize(width: bounds.width, height: bounds.height),
                                                 decorations: graphiteFrame ? .none : .system,
                                                 makeScene: { _ in scene }) else { return nil }
        scene.drawsWindowFrame = graphiteFrame
        dispatcher.attach(scene)
        let previousDetach = scene.onDetach
        scene.onDetach = { [weak dispatcher, weak scene] in
            if let dispatcher, let scene { dispatcher.detach(scene) }
            previousDetach()
        }
        return host
    }
}
