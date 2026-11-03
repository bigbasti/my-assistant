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
        let old = #"{"settings":{"playTone":false}}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(PersistedState.self, from: old)
        #expect(!s.settings.playTone)
        #expect(s.settings.enabled == Set(SourceKind.allCases))
        #expect(s.settings.reserveScreenSpace)
        #expect(!s.settings.launchAtLogin)
        let empty = try JSONDecoder().decode(PersistedState.self, from: "{}".data(using: .utf8)!)
        #expect(empty.settings == AppSettings())
    }

    @Test func oldStateWithGraphKeysDecodes() throws {
        let old = #"{"deltaLinks":{"mail":"https://x/d"},"teamsLastSeen":{"c":"1"},"dismissedEventIDs":["e1"],"settings":{"clientID":"abc","tenantID":"t","playTone":false,"launchAtLogin":true}}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(PersistedState.self, from: old)
        #expect(s.dismissedEventIDs == ["e1"])
        #expect(!s.settings.playTone)
        #expect(s.settings.launchAtLogin)
        #expect(s.settings.enabled == Set(SourceKind.allCases))
    }

    struct LoginError: Error {}

    func make(login: FakeLoginItem = FakeLoginItem()) -> (SettingsController, Effects, AppModel) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("set-\(UUID()).json")
        let m = AppModel(persistence: Persistence(url: url))
        let e = Effects()
        let c = SettingsController(model: m, restartSources: { e.restarts += 1 }, dockTo: { e.edges.append($0) },
                                   setReserving: { e.reserving.append($0) }, loginItem: login)
        return (c, e, m)
    }

    @Test func togglingSourceRestartsSources() {
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
        login.failure = LoginError()
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
}
