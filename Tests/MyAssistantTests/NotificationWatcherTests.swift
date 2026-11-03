import Testing
import Foundation
@testable import MyAssistantCore

@MainActor @Suite struct NotificationWatcherTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    final class Fake: @unchecked Sendable {
        var result: Result<[AlertRecord], NotificationDBError> = .success([])
        var calls: [[String]] = []
        func read(_ b: [String]) throws(NotificationDBError) -> [AlertRecord] {
            calls.append(b)
            return try result.get()
        }
    }

    func rec(_ id: String, _ bundle: String, age: TimeInterval = 60) -> AlertRecord {
        AlertRecord(uuidHex: id, bundleID: bundle, delivered: Date(timeIntervalSince1970: 1_800_000_000 - age),
                    title: "T", subtitle: "S", body: "B", category: nil, archivedStrings: [])
    }

    func make(_ f: Fake) -> (AppModel, NotificationWatcher) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nw-\(UUID().uuidString).json")
        let m = AppModel(persistence: Persistence(url: url), now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let w = NotificationWatcher(model: m, read: { (b: [String]) throws(NotificationDBError) -> [AlertRecord] in try f.read(b) }, now: { Date(timeIntervalSince1970: 1_800_000_000) },
                                  dbPath: "/nonexistent/\(UUID().uuidString)/db")
        return (m, w)
    }

    @Test func ingestsTeamsAndMail() {
        let f = Fake(); f.result = .success([rec("a", "com.microsoft.teams2"), rec("b", "com.microsoft.outlook")])
        let (m, w) = make(f)
        w.readNow()
        #expect(Set(m.notifications.visible.map(\.id)) == ["teams:a", "mail:b"])
        #expect(m.status[.teams] == .ok(t0))
        #expect(m.status[.mail] == .ok(t0))
        #expect(m.state.bootstrappedSources == [.teams, .mail])
    }

    @Test func bootstrapOnlyIngestsFresh() {
        let f = Fake(); f.result = .success([rec("old", "com.microsoft.outlook", age: 30 * 3600)])
        let (m, w) = make(f)
        w.readNow()
        #expect(m.notifications.visible.isEmpty)
        w.readNow()
        #expect(m.notifications.visible.map(\.id) == ["mail:old"])
    }

    @Test func clearedRecordKeepsCard() {
        let f = Fake(); f.result = .success([rec("a", "com.microsoft.outlook")])
        let (m, w) = make(f)
        w.readNow()
        f.result = .success([])
        w.readNow()
        #expect(m.notifications.visible.map(\.id) == ["mail:a"])
    }

    @Test func busyErrorKeepsStatusAndItems() {
        let f = Fake(); f.result = .success([rec("a", "com.microsoft.outlook")])
        let (m, w) = make(f)
        w.readNow()
        f.result = .failure(.busy)
        w.readNow()
        #expect(m.status[.mail] == .ok(t0))
        #expect(m.notifications.visible.count == 1)
    }

    @Test func accessDeniedSetsStatus() {
        let f = Fake(); f.result = .failure(.accessDenied)
        let (m, w) = make(f)
        w.readNow()
        #expect(m.status[.teams] == .needsFullDiskAccess)
        #expect(m.status[.mail] == .needsFullDiskAccess)
    }

    @Test func failedSetsErrorStatus() {
        let f = Fake(); f.result = .failure(.failed(11))
        let (m, w) = make(f)
        w.readNow()
        #expect(m.status[.mail] == .error("Notification database error 11"))
    }

    @Test func disabledSourceNotRead() {
        let f = Fake()
        let (m, w) = make(f)
        m.settings.enabled.remove(.mail)
        w.readNow()
        #expect(f.calls == [["com.microsoft.teams2"]])
        #expect(m.status[.mail] == .disabled)
    }

    @Test func noAlertsYetUntilFirstRecord() {
        let f = Fake()
        let (m, w) = make(f)
        w.readNow()
        #expect(m.status[.teams] == .noAlertsYet)
        #expect(m.status[.mail] == .noAlertsYet)
        f.result = .success([rec("a", "com.microsoft.teams2")])
        w.readNow()
        #expect(m.status[.teams] == .ok(t0))
        #expect(m.status[.mail] == .noAlertsYet)
    }

    @Test func startWithMissingPathsDoesNotCrash() {
        let f = Fake()
        let (_, w) = make(f)
        w.start()
        w.stop()
    }
}
