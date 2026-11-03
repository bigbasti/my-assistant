import SwiftUI
import AppKit

public struct SettingsView: View {
    @State private var controller: SettingsController

    public init(controller: SettingsController) { _controller = State(initialValue: controller) }

    public var body: some View {
        TabView {
            AccountsTab(c: controller)
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            SourcesTab(c: controller)
                .tabItem { Label("Sources", systemImage: "tray.full") }
            GeneralTab(c: controller)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 400)
    }
}

private struct AccountsTab: View {
    let c: SettingsController
    @State private var clientID = ""
    @State private var tenantID = ""
    @FocusState private var focus: Field?
    private enum Field { case client, tenant }

    private func commit() { Task { await c.applyAccount(clientID: clientID, tenantID: tenantID) } }

    var body: some View {
        Form {
            Section("Microsoft Entra app") {
                TextField("Client ID", text: $clientID).focused($focus, equals: .client)
                TextField("Tenant ID", text: $tenantID).focused($focus, equals: .tenant)
                if clientID != c.model.settings.clientID || tenantID != c.model.settings.tenantID {
                    Text("Changing these signs you out.").font(.callout).foregroundStyle(.secondary)
                }
                Text("Register an app in Entra ID as a public client with redirect URI myassistant://auth and delegated permissions User.Read, Mail.Read, Calendars.Read, Chat.Read and offline_access.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Account") {
                if let upn = c.upn {
                    LabeledContent("Signed in as", value: upn)
                }
                HStack {
                    Button("Sign in") { Task { await c.applyAccount(clientID: clientID, tenantID: tenantID); await c.signIn() } }.disabled(c.isSigningIn)
                    Button("Sign out") { Task { await c.signOut() } }
                    if c.isSigningIn { ProgressView().controlSize(.small) }
                }
                if let e = c.signInError {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                if !c.consentRequiredSources.isEmpty {
                    Label("Consent required: an administrator must grant permissions for \(c.consentRequiredSources.map(\.rawValue).joined(separator: ", ")).",
                          systemImage: "lock.shield").foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { clientID = c.model.settings.clientID; tenantID = c.model.settings.tenantID }
        .onSubmit { commit() }
        .onChange(of: focus) { _, _ in commit() }
        .task { await c.loadUPN() }
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
        case .signedOut: "Signed out"
        case .ok(let d): "Updated \(d.formatted(date: .omitted, time: .standard))"
        case .error(let m): "Error: \(m)"
        case .consentRequired: "Consent required"
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
