import Testing
import Foundation
@testable import MyAssistantCore

final class FakeLoginItem: LoginItem {
    var isEnabled = false
    var failure: Error?
    func set(_ on: Bool) throws {
        if let failure { throw failure }
        isEnabled = on
    }
}

@MainActor final class Effects {
    var restarts = 0
    var edges: [DockEdge] = []
    var reserving: [Bool] = []
}

@MainActor @Suite struct SettingsTests {
    @Test func settingsDecodeWithMissingKeys() throws {
        let old = #"{"settings":{"clientID":"abc"}}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(PersistedState.self, from: old)
        #expect(s.settings.clientID == "abc")
        #expect(s.settings.tenantID == "organizations")
        #expect(s.settings.enabled == Set(SourceKind.allCases))
        #expect(s.settings.reserveScreenSpace)
        #expect(s.settings.playTone)
        #expect(!s.settings.launchAtLogin)
        let empty = try JSONDecoder().decode(PersistedState.self, from: "{}".data(using: .utf8)!)
        #expect(empty.settings == AppSettings())
    }

    func make(login: FakeLoginItem = FakeLoginItem(), signIn: @escaping @MainActor (OAuth) async throws -> Void = { _ in },
              upn: @escaping @MainActor (OAuth) async -> String? = { _ in "me@x.com" }) -> (SettingsController, Effects, AppModel) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("set-\(UUID()).json")
        let m = AppModel(persistence: Persistence(url: url))
        let e = Effects()
        let c = SettingsController(model: m, restartPoller: { e.restarts += 1 }, dockTo: { e.edges.append($0) },
                                   setReserving: { e.reserving.append($0) }, loginItem: login,
                                   performSignIn: signIn, fetchUPN: upn)
        return (c, e, m)
    }

    @Test func clientIDChangeRebuildsOAuthWithoutSignIn() {
        let (c, e, m) = make()
        #expect(m.oauth == nil)
        c.setClientID("client-1")
        #expect(m.oauth != nil)
        #expect(m.settings.clientID == "client-1")
        #expect(e.restarts == 0)
        let first = m.oauth
        c.setTenantID("contoso.com")
        #expect(m.oauth !== first)
    }

    @Test func togglingSourceRestartsPoller() {
        let (c, e, m) = make()
        c.setSource(.mail, enabled: false)
        #expect(!m.settings.enabled.contains(.mail))
        #expect(e.restarts == 1)
        c.setSource(.mail, enabled: true)
        #expect(m.settings.enabled.contains(.mail))
        #expect(e.restarts == 2)
    }

    @Test func reserveToggleAttachesAndDetaches() {
        let (c, e, m) = make()
        c.setReserveScreenSpace(false)
        c.setReserveScreenSpace(true)
        #expect(e.reserving == [false, true])
        #expect(m.settings.reserveScreenSpace)
    }

    @Test func edgePickerDocks() {
        let (c, e, _) = make()
        c.setDockEdge(.right)
        #expect(e.edges == [.right])
    }

    @Test func launchAtLoginFailureRevertsAndShowsError() {
        let login = FakeLoginItem()
        login.failure = GraphError.signedOut
        let (c, _, m) = make(login: login)
        c.setLaunchAtLogin(true)
        #expect(!m.settings.launchAtLogin)
        #expect(c.launchError != nil)
        login.failure = nil
        c.setLaunchAtLogin(true)
        #expect(m.settings.launchAtLogin)
        #expect(c.launchError == nil)
    }

    @Test func launchAtLoginSyncsFromSystem() {
        let login = FakeLoginItem()
        login.isEnabled = true
        let (c, _, m) = make(login: login)
        c.syncLaunchAtLogin()
        #expect(m.settings.launchAtLogin)
    }

    @Test func signInValidatesFirst() async {
        var called = false
        let (c, e, _) = make(signIn: { _ in called = true })
        c.setClientID("bad id!")
        await c.signIn()
        #expect(!called)
        #expect(c.signInError == "Invalid client ID")
        #expect(e.restarts == 0)
    }

    @Test func signInSuccessShowsUPNAndRestarts() async {
        let (c, e, _) = make()
        c.setClientID("client-1")
        await c.signIn()
        #expect(c.signInError == nil)
        #expect(c.upn == "me@x.com")
        #expect(e.restarts == 1)
        await c.signOut()
        #expect(c.upn == nil)
        #expect(e.restarts == 2)
    }

    @Test func signInFailureShowsError() async {
        let (c, e, _) = make(signIn: { _ in throw GraphError.unauthorized })
        c.setClientID("client-1")
        await c.signIn()
        #expect(c.signInError != nil)
        #expect(e.restarts == 0)
    }

    @Test func consentRequiredSurfacesFromStatus() {
        let (c, _, m) = make()
        m.status[.teams] = .consentRequired
        #expect(c.consentRequiredSources == [.teams])
    }
}
