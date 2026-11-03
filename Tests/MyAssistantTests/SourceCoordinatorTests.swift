import Testing
import Foundation
@testable import MyAssistantCore

@MainActor @Suite struct SourceCoordinatorTests {
    final class Fake: @unchecked Sendable {
        var calls = 0
        func read(_ b: [String]) throws(NotificationDBError) -> [AlertRecord] { calls += 1; return [] }
    }

    func make(_ f: Fake) -> (AppModel, SourceCoordinator) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sc-\(UUID().uuidString).json")
        let m = AppModel(persistence: Persistence(url: url))
        let w = NotificationWatcher(model: m, read: { (b: [String]) throws(NotificationDBError) -> [AlertRecord] in try f.read(b) },
                                    dbPath: "/nonexistent/\(UUID().uuidString)/db")
        let c = CalendarReader(model: m)
        return (m, SourceCoordinator(model: m, watcher: w, calendar: c))
    }

    @Test func disabledCalendarNotStarted() {
        let (m, c) = make(Fake())
        m.settings.enabled = [.teams, .mail]
        c.start()
        defer { c.stop() }
        #expect(m.status[.calendar] == .disabled)
    }

    @Test func restartAppliesToggles() {
        let f = Fake()
        let (m, c) = make(f)
        m.settings.enabled = [.teams]
        c.start()
        defer { c.stop() }
        #expect(m.status[.teams] == .noAlertsYet)
        #expect(m.status[.mail] == .disabled)
        #expect(m.status[.calendar] == .disabled)
        m.settings.enabled = [.mail]
        c.restart()
        #expect(m.status[.teams] == .disabled)
        #expect(m.status[.mail] == .noAlertsYet)
    }

    @Test func nothingEnabledNeverReads() {
        let f = Fake()
        let (m, c) = make(f)
        m.settings.enabled = []
        c.start()
        defer { c.stop() }
        #expect(f.calls == 0)
        #expect(SourceKind.allCases.allSatisfy { m.status[$0] == .disabled })
    }
}
