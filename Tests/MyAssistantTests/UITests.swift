import Testing
import Foundation
@testable import MyAssistantCore

@MainActor @Suite struct UITests {
    @Test func countdownLabelFormats() {
        #expect(countdownLabel(272) == "04:32")
        #expect(countdownLabel(59.2) == "01:00")
        #expect(countdownLabel(-5) == "00:00")
    }
    @Test func glowsWhileYoungerThanTenMinutes() {
        let n = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(isFreshMessage(surfacedAt: n.addingTimeInterval(-599), now: n))
        #expect(!isFreshMessage(surfacedAt: n.addingTimeInterval(-600), now: n))
        #expect(isFreshMessage(surfacedAt: n, now: n))
    }
    @Test func relativeTimeStrings() {
        let n = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(relativeTime(from: n.addingTimeInterval(-10), now: n) == "now")
        #expect(relativeTime(from: n.addingTimeInterval(-300), now: n) == "5 min ago")
        #expect(relativeTime(from: n.addingTimeInterval(-7300), now: n) == "2 h ago")
        #expect(relativeTime(from: n.addingTimeInterval(-90000), now: n) == "1 d ago")
    }
    @Test func tickPlaysToneOncePerStartedEvent() {
        var t = Date(timeIntervalSince1970: 1_800_000_000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ui-\(UUID()).json")
        let m = AppModel(persistence: Persistence(url: url), now: { t })
        var count = 0
        m.playTone = { count += 1 }
        m.events.replace([CalendarEvent(id: "e", subject: "s", start: t.addingTimeInterval(10), end: t.addingTimeInterval(1800))])
        m.tick(); #expect(count == 0)
        t = t.addingTimeInterval(11)
        m.tick(); m.tick(); #expect(count == 1)
        m.settings.playTone = false
        m.events.replace([CalendarEvent(id: "f", subject: "s", start: t, end: t.addingTimeInterval(60))])
        m.tick(); #expect(count == 1)
    }
}
