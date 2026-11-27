import CacaoHost
import GraphiteBase
import GraphiteQuickDraw
import GraphiteWindows
import GraphiteDialogs
import GraphiteCacaoHost

@main
struct GraphiteDialogDemo {
    @MainActor
    static func main() {
        let manager = WindowManager(quickDraw: QuickDraw(screens: [GraphicsDevice.screen(width: 1024, height: 768)]))
        let dialog = Dialog(kind: .modeless,
                            bounds: Rect(top: 100, left: 100, bottom: 310, right: 500),
                            title: "Graphite Dialog Demo", items: [
            DialogItem(bounds: Rect(top: 20, left: 20, bottom: 43, right: 370), kind: .staticText, text: "Enter text, then click Apply or press Return:"),
            DialogItem(bounds: Rect(top: 50, left: 20, bottom: 75, right: 370), kind: .editText, text: "Hello, Graphite!"),
            DialogItem(bounds: Rect(top: 90, left: 20, bottom: 112, right: 200), kind: .checkBox, text: "Remember this choice"),
            DialogItem(bounds: Rect(top: 125, left: 20, bottom: 150, right: 370), kind: .staticText, text: "Ready."),
            DialogItem(bounds: Rect(top: 170, left: 210, bottom: 196, right: 285), kind: .button, text: "Close"),
            DialogItem(bounds: Rect(top: 170, left: 300, bottom: 196, right: 375), kind: .button, text: "Apply")
        ])
        dialog.defaultItem = 6
        dialog.cancelItem = 5
        do { try dialog.attach(to: manager) }
        catch { print("Could not create dialog: \(error)"); return }
        let dispatcher = ToolboxEventDispatcher(windows: manager, itemHit: { dialog, item in
            switch item {
            case 3:
                if let control = dialog.control(of: item) {
                    control.maximum = 1
                    control.value = control.value == 0 ? 1 : 0
                }
            case 5: HostRuntime.quit()
            case 6: dialog.setText(dialog.text(of: 2) ?? "", of: 4)
            default: break
            }
        })
        guard let scene = ToolboxScene(dialog: dialog, onItemHit: { _ in }) else { return }
        HostRuntime.run {
            if ToolboxWindowHost.present(scene, dispatcher: dispatcher, graphiteFrame: CommandLine.arguments.contains("--graphite-frame")) == nil {
                print("Could not open the demo window.")
            }
        }
        withExtendedLifetime((manager, dialog, scene, dispatcher)) {}
    }
}
