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
            Section("Sources") {
                ForEach(SourceKind.allCases, id: \.self) { kind in
                    Toggle(isOn: Binding(get: { c.model.settings.enabled.contains(kind) },
                                         set: { c.setSource(kind, enabled: $0) })) {
                        HStack {
                            Circle().fill(kind.color).frame(width: 10, height: 10)
                            Text(kind.rawValue.capitalized)
                            Spacer()
                            Text(statusText(c.model.status[kind])).foregroundStyle(.secondary).font(.callout)
                        }
                    }
                }
                Button("Refresh now") { c.refresh() }
            }
        }
        .formStyle(.grouped)
    }

    private func statusText(_ s: SourceStatus?) -> String {
        switch s {
        case nil: "—"
        case .disabled: "Disabled"
        case .noAlertsYet: "No alerts yet"
        case .needsFullDiskAccess: "Full Disk Access needed"
        case .needsCalendarAccess: "Calendar access needed"
        case .ok(let d): "Updated \(d.formatted(date: .omitted, time: .standard))"
        case .error(let m): "Error: \(m)"
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
