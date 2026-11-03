import SwiftUI
import AppKit

public struct SettingsView: View {
    @State private var controller: SettingsController

    public init(controller: SettingsController) { _controller = State(initialValue: controller) }

    public var body: some View {
        TabView {
            SourcesTab(c: controller)
                .tabItem { Label("Sources", systemImage: "tray.full") }
            GeneralTab(c: controller)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 400)
    }
}

private struct SourcesTab: View {
    let c: SettingsController

    var body: some View {
        Form {
            ForEach(SourceKind.allCases, id: \.self) { kind in
                Section {
                    Toggle(isOn: Binding(get: { c.model.settings.enabled.contains(kind) },
                                         set: { c.setSource(kind, enabled: $0) })) {
                        HStack {
                            Circle().fill(kind.color).frame(width: 10, height: 10)
                            Text(title(kind))
                        }
                    }
                    let st = c.model.status[kind] ?? .disabled
                    let (text, color) = describe(st)
                    HStack(spacing: 6) {
                        if case .ok = st { Circle().fill(.green).frame(width: 8, height: 8) }
                        Text(text).foregroundStyle(color).font(.callout)
                    }
                    if st == .needsFullDiskAccess {
                        Button("Open Full Disk Access settings…") { c.openFullDiskAccessSettings() }
                    }
                    if st == .needsCalendarAccess {
                        Button("Grant Calendar access…") { Task { await c.fixCalendarAccess() } }
                    }
                }
            }
            Section {
                Text("Turn on notifications for Outlook and Teams in System Settings → Notifications (banners may be set to None; alerts still arrive).")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func title(_ k: SourceKind) -> String {
        switch k {
        case .teams: "Teams"
        case .mail: "Outlook mail"
        case .calendar: "Calendar"
        }
    }

    private func describe(_ s: SourceStatus) -> (String, Color) {
        switch s {
        case .disabled: return ("Off", Color.secondary)
        case .noAlertsYet: return ("No alerts seen yet", Color.secondary)
        case .needsFullDiskAccess: return ("Full Disk Access needed", Color.orange)
        case .needsCalendarAccess: return ("Calendar access needed", Color.orange)
        case .ok(let d):
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .abbreviated
            return ("Working · updated \(f.localizedString(for: d, relativeTo: Date()))", Color.primary)
        case .error(let m): return (m, Color.red)
        }
    }
}

private struct GeneralTab: View {
    let c: SettingsController

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { c.model.settings.launchAtLogin }, set: { c.setLaunchAtLogin($0) }))
                if let e = c.launchError {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
                }
                Picker("Dock edge", selection: Binding(get: { c.model.state.dock?.edge ?? .left }, set: { c.setDockEdge($0) })) {
                    Text("Left").tag(DockEdge.left)
                    Text("Right").tag(DockEdge.right)
                }
                Toggle("Reserve screen space (requires Accessibility)",
                       isOn: Binding(get: { c.model.settings.reserveScreenSpace }, set: { c.setReserveScreenSpace($0) }))
                Button("Open Accessibility Settings…") {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(u)
                    }
                }
                Toggle("Play tone at meeting start",
                       isOn: Binding(get: { c.model.settings.playTone }, set: { c.setPlayTone($0) }))
            }
        }
        .formStyle(.grouped)
        .onAppear { c.syncLaunchAtLogin() }
    }
}
