import Testing
import Foundation
import CoreGraphics
@testable import MyAssistantCore

@MainActor @Suite struct FinalFixTests {
    @Test func trustDecision() {
        let s = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(ScreenReserver.shouldStartEnforcing(trusted: true, strip: s, enforcing: false))
        #expect(!ScreenReserver.shouldStartEnforcing(trusted: false, strip: s, enforcing: false))
        #expect(!ScreenReserver.shouldStartEnforcing(trusted: true, strip: nil, enforcing: false))
        #expect(!ScreenReserver.shouldStartEnforcing(trusted: true, strip: s, enforcing: true))
    }

    @Test func recheckWithoutStripDoesNothing() {
        var asked = 0
        let r = ScreenReserver(isTrusted: { asked += 1; return true })
        r.recheckTrust()
        #expect(asked == 0 && !r.isWatchingTrust)
    }

    @Test func corruptStateIsQuarantined() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("state.json")
        try Data("{not json".utf8).write(to: url)
        let s = Persistence(url: url).load()
        #expect(s == PersistedState())
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(!names.contains("state.json"))
        let bad = names.filter { $0.hasPrefix("state.corrupt-") && $0.hasSuffix(".json") }
        #expect(bad.count == 1)
        #expect(try String(contentsOf: dir.appendingPathComponent(bad[0]), encoding: .utf8) == "{not json")
    }

    @Test func replacePrunesDismissedIDs() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        func ev(_ id: String) -> CalendarEvent { CalendarEvent(id: id, subject: id, start: t0, end: t0.addingTimeInterval(3600), isAllDay: false) }
        let s = EventStore(state: PersistedState(), now: { t0 })
        s.replace([ev("a"), ev("b")])
        s.dismiss("a"); s.dismiss("b")
        s.replace([ev("b")])
        var st = PersistedState()
        s.exportState(into: &st)
        #expect(st.dismissedEventIDs == ["b"])
    }
}
