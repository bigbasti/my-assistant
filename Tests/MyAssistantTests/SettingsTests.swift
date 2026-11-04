import Testing
import Foundation
import EventKit
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
    var opened: [URL] = []
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

    func make(login: FakeLoginItem = FakeLoginItem(), auth: EKAuthorizationStatus = .denied,
              opener: (@MainActor (URL) -> Void)? = nil) -> (SettingsController, Effects, AppModel) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("set-\(UUID()).json")
        let m = AppModel(persistence: Persistence(url: url))
        let e = Effects()
        let c = SettingsController(model: m, restartSources: { e.restarts += 1 }, dockTo: { e.edges.append($0) },
                                   setReserving: { e.reserving.append($0) }, loginItem: login,
                                   openURL: opener ?? { e.opened.append($0) }, calendarAuthorization: { auth })
        return (c, e, m)
    }

    @Test func hideFromScreenSharingDefaultsOn() throws {
        let old = #"{"settings":{"playTone":false}}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(PersistedState.self, from: old).settings.hideFromScreenSharing)
        #expect(AppSettings().hideFromScreenSharing)
    }

    @Test func hideFromScreenSharingIsSaved() {
        let (c, _, m) = make()
        c.setHideFromScreenSharing(false)
        #expect(!m.settings.hideFromScreenSharing)
        #expect(m.persistence.hasPendingSave)
    }

    @Test func sharingTypeRule() {
        #expect(ScreenSharingGuard.sharingType(hide: true, isSettingsWindow: false) == .none)
        #expect(ScreenSharingGuard.sharingType(hide: true, isSettingsWindow: true) == .readOnly)
        #expect(ScreenSharingGuard.sharingType(hide: false, isSettingsWindow: false) == .readOnly)
    }

    @Test func backgroundOpacityDefaultsToClearGlass() throws {
        let old = #"{"settings":{"playTone":false}}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(PersistedState.self, from: old).settings.backgroundOpacity == 0)
    }

    @Test func backgroundOpacityIsClampedAndSaved() {
        let (c, _, m) = make()
        c.setBackgroundOpacity(0.6)
        #expect(m.settings.backgroundOpacity == 0.6)
        c.setBackgroundOpacity(1.7)
        #expect(m.settings.backgroundOpacity == 1)
        c.setBackgroundOpacity(-0.2)
        #expect(m.settings.backgroundOpacity == 0)
        #expect(m.persistence.hasPendingSave)
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

    @Test func fullDiskAccessButtonOpensPrivacyAllFiles() {
        let (c, e, _) = make()
        c.openFullDiskAccessSettings()
        #expect(e.opened.map(\.absoluteString) == ["x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"])
    }

    @Test func calendarFixOpensSettingsWhenDenied() async {
        let (c, e, _) = make(auth: .denied)
        await c.fixCalendarAccess()
        #expect(e.opened.map(\.absoluteString) == ["x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"])
        #expect(e.restarts == 0)
    }

    @Test func calendarFixRequestsWhenNotDetermined() async {
        let (c, e, _) = make(auth: .notDetermined)
        await c.fixCalendarAccess()
        #expect(e.restarts == 1)
        #expect(e.opened.isEmpty)
    }

    @Test func toggleRestartsSources() {
        let (c, e, _) = make()
        c.setSource(.teams, enabled: false)
        #expect(e.restarts == 1)
    }

    @Test func disablingCalendarClearsEvents() {
        let (c, _, m) = make()
        m.events.replace([CalendarEvent(id: "e", subject: "t", start: Date().addingTimeInterval(600), end: Date().addingTimeInterval(1200))])
        #expect(!m.events.today.isEmpty)
        c.setSource(.calendar, enabled: false)
        #expect(m.events.today.isEmpty)
    }
}
