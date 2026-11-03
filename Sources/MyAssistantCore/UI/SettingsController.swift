import Foundation
import Observation

@Observable @MainActor
public final class SettingsController {
    public let model: AppModel
    public private(set) var upn: String?
    public private(set) var signInError: String?
    public private(set) var launchError: String?
    public private(set) var isSigningIn = false

    @ObservationIgnored private let restartPoller: @MainActor () -> Void
    @ObservationIgnored private let dockTo: @MainActor (DockEdge) -> Void
    @ObservationIgnored private let setReserving: @MainActor (Bool) -> Void
    @ObservationIgnored private let loginItem: LoginItem
    @ObservationIgnored private let performSignIn: @MainActor (OAuth) async throws -> Void
    @ObservationIgnored private let fetchUPN: @MainActor (OAuth) async -> String?

    public init(model: AppModel,
                restartPoller: @escaping @MainActor () -> Void,
                dockTo: @escaping @MainActor (DockEdge) -> Void,
                setReserving: @escaping @MainActor (Bool) -> Void,
                loginItem: LoginItem = SystemLoginItem(),
                performSignIn: @escaping @MainActor (OAuth) async throws -> Void = { try await $0.signIn() },
                fetchUPN: @escaping @MainActor (OAuth) async -> String? = SettingsController.graphUPN) {
        self.model = model
        self.restartPoller = restartPoller
        self.dockTo = dockTo
        self.setReserving = setReserving
        self.loginItem = loginItem
        self.performSignIn = performSignIn
        self.fetchUPN = fetchUPN
    }

    private struct Me: Decodable { let userPrincipalName: String? }

    public static func graphUPN(_ oauth: OAuth) async -> String? {
        let client = GraphClient(tokens: oauth, transport: URLSession.shared)
        return try? await client.get("/me?$select=userPrincipalName", as: Me.self).userPrincipalName
    }

    private func changed() { model.save() }

    public func setClientID(_ v: String) {
        guard model.settings.clientID != v else { return }
        model.settings.clientID = v
        model.rebuildOAuth()
        upn = nil
        changed()
    }

    public func setTenantID(_ v: String) {
        guard model.settings.tenantID != v else { return }
        model.settings.tenantID = v
        model.rebuildOAuth()
        upn = nil
        changed()
    }

    public func setSource(_ kind: SourceKind, enabled: Bool) {
        if enabled { model.settings.enabled.insert(kind) } else { model.settings.enabled.remove(kind) }
        changed()
        restartPoller()
    }

    public func setReserveScreenSpace(_ on: Bool) {
        model.settings.reserveScreenSpace = on
        changed()
        setReserving(on)
    }

    public func setDockEdge(_ edge: DockEdge) {
        dockTo(edge)
        changed()
    }

    public func setPlayTone(_ on: Bool) {
        model.settings.playTone = on
        changed()
    }

    public func setLaunchAtLogin(_ on: Bool) {
        launchError = nil
        do {
            try loginItem.set(on)
            model.settings.launchAtLogin = on
        } catch {
            launchError = error.localizedDescription
            model.settings.launchAtLogin = loginItem.isEnabled
        }
        changed()
    }

    public func syncLaunchAtLogin() {
        let on = loginItem.isEnabled
        if model.settings.launchAtLogin != on {
            model.settings.launchAtLogin = on
            changed()
        }
    }

    public func signIn() async {
        signInError = nil
        let s = model.settings
        do {
            try OAuthRequests.validate(clientID: s.clientID, tenantID: s.tenantID)
        } catch GraphError.invalidConfiguration(let m) {
            signInError = m
            return
        } catch {
            signInError = error.localizedDescription
            return
        }
        if model.oauth == nil { model.rebuildOAuth() }
        guard let oauth = model.oauth else { signInError = "Enter a client ID first"; return }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await performSignIn(oauth)
        } catch {
            signInError = (error as? GraphError) == .unauthorized ? "Sign-in failed or was cancelled" : error.localizedDescription
            return
        }
        upn = await fetchUPN(oauth)
        restartPoller()
    }

    public func signOut() async {
        await model.oauth?.signOut()
        upn = nil
        signInError = nil
        restartPoller()
    }

    public func refresh() { restartPoller() }

    public func loadUPN() async {
        guard upn == nil, let oauth = model.oauth else { return }
        upn = await fetchUPN(oauth)
    }

    public var consentRequiredSources: [SourceKind] {
        SourceKind.allCases.filter { model.status[$0] == .consentRequired }
    }
}
