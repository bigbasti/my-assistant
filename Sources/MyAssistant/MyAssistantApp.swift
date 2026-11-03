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

    lazy var settingsController = SettingsController(
        model: model,
        restartPoller: { [poller] in poller.start() },
        dockTo: { [dock] edge in
            dock.dock(to: DockPlacement(screenID: dock.placement.screenID, edge: edge), animated: true)
        },
        setReserving: { [dock, reserver] on in
            if on {
                dock.reserver = reserver
                dock.dock(to: dock.placement, animated: false)
            } else {
                dock.reserver = nil
                reserver.reserve(nil)
            }
        })

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
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
            Button("Dock Left") { dockTo(.left) }
            Button("Dock Right") { dockTo(.right) }
#if DEBUG
            Divider()
            Button("Inject sample data") { delegate.model.injectSampleData() }
#endif
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        Settings { SettingsView(controller: delegate.settingsController) }
    }
}
