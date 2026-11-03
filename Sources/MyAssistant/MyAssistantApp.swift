import AppKit
import MyAssistantCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct MyAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("My Assistant", systemImage: "sparkles") {
            SettingsLink { Text("Settings…") }
            Button("Dock Left") {}
            Button("Dock Right") {}
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        Settings { SettingsView() }
    }
}
