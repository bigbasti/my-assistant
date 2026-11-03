import AppKit
import MyAssistantCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let reserver = ScreenReserver()
    let model = AppModel(persistence: Persistence(url: Persistence.defaultURL))
    lazy var poller = Poller(model: model)
    lazy var dock: DockController = {
        let d = DockController(content: RootView(model: model), placement: model.state.dock)
        if model.settings.reserveScreenSpace { d.reserver = reserver }
        d.onPlacementChange = { [model] p in
            model.state.dock = p
            model.save()
        }
        return d
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        dock.show()
        model.startTimer()
        poller.start()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.flush()
    }
}

@main
struct MyAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private func dockTo(_ edge: DockEdge) {
        let id = delegate.dock.placement.screenID
        delegate.dock.dock(to: DockPlacement(screenID: id, edge: edge), animated: true)
    }

    var body: some Scene {
        MenuBarExtra("My Assistant", systemImage: "sparkles") {
            SettingsLink { Text("Settings…") }
            Button("Dock Left") { dockTo(.left) }
            Button("Dock Right") { dockTo(.right) }
#if DEBUG
            Divider()
            Button("Inject sample data") { delegate.model.injectSampleData() }
#endif
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        Settings { SettingsView() }
    }
}
