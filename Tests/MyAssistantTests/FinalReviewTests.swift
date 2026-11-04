import Testing
import Foundation
@testable import MyAssistantCore

@MainActor @Suite struct FinalReviewTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func note(_ k: SourceKind, url: URL? = nil) -> AssistantNotification {
        AssistantNotification(id: "x", kind: k, title: "t", sender: "s", preview: "p", openURL: url, firstSurfacedAt: t0, surfacedAt: t0)
    }

    func model() -> AppModel {
        AppModel(persistence: Persistence(url: FileManager.default.temporaryDirectory.appendingPathComponent("ff-\(UUID()).json")))
    }

    func rec(_ id: String, _ bundle: String, age: TimeInterval) -> AlertRecord {
        AlertRecord(uuidHex: id, bundleID: bundle, delivered: t0.addingTimeInterval(-age),
                    title: "T", subtitle: "S", body: "B", category: nil, archivedStrings: [])
    }

    final class Fake: @unchecked Sendable {
        var records: [AlertRecord] = []
        func read(_ b: [String]) throws(NotificationDBError) -> [AlertRecord] { records }
    }

    func watcher(_ m: AppModel, _ f: Fake) -> NotificationWatcher {
        NotificationWatcher(model: m, read: { (b: [String]) throws(NotificationDBError) -> [AlertRecord] in try f.read(b) },
                            now: { Date(timeIntervalSince1970: 1_800_000_000) }, dbPath: "/nonexistent/\(UUID())/db")
    }

    @Test func mailCardLaunchesOutlook() async {
        let m = model(); var launched: [String] = []; var opened: [URL?] = []
        m.launchApp = { launched.append($0) }; m.opener = { opened.append($0) }
        // Not found in Apple Mail (default) → Outlook opens.
        await m.openMail(m.notificationQuery(note(.mail)))
        #expect(launched == ["com.microsoft.Outlook"] && opened.isEmpty)
    }

    @Test func teamsWithoutURLLaunchesTeams() {
        let m = model(); var launched: [String] = []
        m.launchApp = { launched.append($0) }
        m.open(note(.teams))
        #expect(launched == ["com.microsoft.teams2"])
    }

    @Test func legacyTeamsLinkGainsChatContext() {
        let m = model(); var opened: [URL?] = []
        m.opener = { opened.append($0) }
        m.open(note(.teams, url: URL(string: "msteams:/l/message/19%3Aa%40unq.gbl.spaces/123")!))
        #expect(opened == [URL(string: "msteams:/l/message/19%3Aa%40unq.gbl.spaces/123?context=%7B%22contextType%22%3A%22chat%22%7D")!])
    }

    @Test func cardWithURLOpensURL() {
        let m = model(); var launched: [String] = []; var opened: [URL?] = []
        m.launchApp = { launched.append($0) }; m.opener = { opened.append($0) }
        let u = URL(string: "https://example.com")!
        m.open(note(.teams, url: u))
        #expect(opened == [u] && launched.isEmpty)
    }

    @Test func bootstrapIsPerSource() {
        let m = model(); let f = Fake(); let w = watcher(m, f)
        m.settings.enabled = [.teams]
        w.readNow()
        #expect(m.state.bootstrappedSources == [.teams])
        m.settings.enabled = [.teams, .mail]
        f.records = [rec("old", "com.microsoft.outlook", age: 30 * 3600), rec("new", "com.microsoft.outlook", age: 60)]
        w.readNow()
        #expect(m.notifications.visible.map(\.id) == ["mail:new"])
        #expect(m.state.bootstrappedSources == [.teams, .mail])
    }

    @Test func reenablingSourceAppliesWindowAgain() {
        let m = model(); let f = Fake(); let w = watcher(m, f)
        w.readNow()
        let c = SettingsController(model: m, restartSources: {}, dockTo: { _ in }, setReserving: { _ in })
        c.setSource(.mail, enabled: false)
        #expect(!m.state.bootstrappedSources.contains(.mail))
        c.setSource(.mail, enabled: true)
        f.records = [rec("old", "com.microsoft.outlook", age: 30 * 3600)]
        w.readNow()
        #expect(m.notifications.visible.isEmpty)
    }

    @Test func legacyAlertsBootstrappedDecodes() throws {
        let s = try JSONDecoder().decode(PersistedState.self, from: #"{"alertsBootstrapped":true}"#.data(using: .utf8)!)
        #expect(s.bootstrappedSources == [.teams, .mail])
        let n = try JSONDecoder().decode(PersistedState.self, from: "{}".data(using: .utf8)!)
        #expect(n.bootstrappedSources.isEmpty && n.sourcesSeen.isEmpty)
    }

    @Test func seenPersistsAcrossRestart() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seen-\(UUID()).json")
        let p = Persistence(url: url)
        let m = AppModel(persistence: p, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let f = Fake(); f.records = [rec("a", "com.microsoft.teams2", age: 60)]
        watcher(m, f).readNow()
        m.flush()
        let m2 = AppModel(persistence: Persistence(url: url), now: { Date(timeIntervalSince1970: 1_800_000_000) })
        f.records = []
        let w2 = watcher(m2, f)
        w2.readNow()
        #expect(m2.status[.teams] == .ok(t0))
        #expect(m2.status[.mail] == .noAlertsYet)
    }
}
