import AppKit
import MyAssistantCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let reserver = ScreenReserver()
    lazy var dock: DockController = {
        let d = DockController(content: DockPlaceholderView())
        d.reserver = reserver
        return d
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        dock.show()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        Settings { SettingsView() }
    }
}
