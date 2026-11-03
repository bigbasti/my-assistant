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
    var signOuts = 0
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
                                   performSignIn: signIn, fetchUPN: upn, signOutHook: { _ in e.signOuts += 1 })
        return (c, e, m)
    }

    @Test func clientIDChangeRebuildsOAuthWithoutSignIn() async {
        let (c, e, m) = make()
        #expect(m.oauth == nil)
        await c.applyAccount(clientID: "client-1", tenantID: "organizations")
        #expect(m.oauth != nil)
        #expect(m.settings.clientID == "client-1")
        let first = m.oauth
        await c.applyAccount(clientID: "client-1", tenantID: "contoso.com")
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
        await c.applyAccount(clientID: "bad id!", tenantID: "organizations")
        await c.signIn()
        #expect(!called)
        #expect(c.signInError == "Invalid client ID")
        #expect(e.restarts == 1)
    }

    @Test func signInSuccessShowsUPNAndRestarts() async {
        let (c, e, _) = make()
        await c.applyAccount(clientID: "client-1", tenantID: "organizations")
        await c.signIn()
        #expect(c.signInError == nil)
        #expect(c.upn == "me@x.com")
        #expect(e.restarts == 2)
        await c.signOut()
        #expect(c.upn == nil)
        #expect(e.restarts == 3)
    }

    @Test func signInFailureShowsError() async {
        let (c, e, _) = make(signIn: { _ in throw GraphError.unauthorized })
        await c.applyAccount(clientID: "client-1", tenantID: "organizations")
        await c.signIn()
        #expect(c.signInError != nil)
        #expect(e.restarts == 1)
    }

    @Test func accountChangeWhileSignedInSignsOutAndRestarts() async {
        let (c, e, m) = make()
        await c.applyAccount(clientID: "client-1", tenantID: "organizations")
        await c.signIn()
        #expect(c.upn == "me@x.com")
        let signOuts = e.signOuts, restarts = e.restarts
        await c.applyAccount(clientID: "client-2", tenantID: "organizations")
        #expect(e.signOuts == signOuts + 1)
        #expect(e.restarts == restarts + 1)
        #expect(c.upn == nil)
        #expect(m.settings.clientID == "client-2")
    }

    @Test func applyingUnchangedAccountIsNoOp() async {
        let (c, e, m) = make()
        await c.applyAccount(clientID: "client-1", tenantID: "organizations")
        let signOuts = e.signOuts, restarts = e.restarts
        let oauth = m.oauth
        await c.applyAccount(clientID: "client-1", tenantID: "organizations")
        await c.applyAccount(clientID: " client-1 ", tenantID: "organizations")
        #expect(e.signOuts == signOuts)
        #expect(e.restarts == restarts)
        #expect(m.oauth === oauth)
    }

    @Test func consentRequiredSurfacesFromStatus() {
        let (c, _, m) = make()
        m.status[.teams] = .error("Consent required")
        #expect(c.consentRequiredSources == [.teams])
    }
}
