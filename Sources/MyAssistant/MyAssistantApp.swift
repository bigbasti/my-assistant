import AppKit
import MyAssistantCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let reserver = ScreenReserver()
    let model = AppModel(persistence: Persistence(url: Persistence.defaultURL))
    lazy var sharingGuard = ScreenSharingGuard(model: model)
    lazy var coordinator = SourceCoordinator(
        model: model,
        watcher: NotificationWatcher(model: model, read: { ids throws(NotificationDBError) in
            try NotificationDatabase().read(bundleIDs: ids)
        }),
        calendar: CalendarReader(model: model))
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
        restartSources: { [coordinator] in coordinator.restart() },
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
        sharingGuard.start()
        model.startTimer()
        coordinator.start()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.flush()
    }
}

// Accessory (menu-bar-only) apps don't come to the front on their own, and gestures
// attached to menu items never fire, so activate and raise the window explicitly.
private struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings
    @MainActor private static var closeObserver: NSObjectProtocol?

    var body: some View {
        Button("Settings…") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            openSettings()
            DispatchQueue.main.async {
                for window in NSApp.windows where window.identifier?.rawValue.contains("Settings") == true {
                    window.level = .floating
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    if let token = Self.closeObserver { NotificationCenter.default.removeObserver(token) }
                    Self.closeObserver = NotificationCenter.default.addObserver(
                        forName: NSWindow.willCloseNotification, object: window, queue: .main
                    ) { [weak window] _ in
                        MainActor.assumeIsolated {
                            window?.level = .normal
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }
                }
            }
        }
        .keyboardShortcut(",")
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
            OpenSettingsButton()
            Button("Dock Left") { dockTo(.left) }
            Button("Dock Right") { dockTo(.right) }
#if DEBUG
            Divider()
            Button("Inject sample data") { delegate.model.injectSampleData() }
            Button("Dump sources") { Diagnostics.dumpSources() }
#endif
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        Settings { SettingsView(controller: delegate.settingsController) }
    }
}
