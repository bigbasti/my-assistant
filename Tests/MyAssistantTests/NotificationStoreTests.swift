import Testing
import Foundation
@testable import MyAssistantCore

@MainActor @Suite struct NotificationStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func n(_ id: String, at: TimeInterval = 0) -> AssistantNotification {
        let d = Date(timeIntervalSince1970: 1_800_000_000 + at)
        return AssistantNotification(id: id, kind: .mail, title: id, sender: "s", preview: "p", firstSurfacedAt: d, surfacedAt: d)
    }
    final class Clock { var now: Date; init(_ d: Date) { now = d } }

    @Test func newestOnTop() {
        let s = NotificationStore(state: PersistedState(), now: { self.t0 })
        s.ingest([n("a", at: 1), n("b", at: 3), n("c", at: 2)])
        #expect(s.visible.map(\.id) == ["b", "c", "a"])
    }
    @Test func markDoneRemovesAndRemembers() {
        let s = NotificationStore(state: PersistedState(), now: { self.t0 })
        s.ingest([n("a")])
        s.markDone("a")
        #expect(s.visible.isEmpty)
        s.ingest([n("a")])
        #expect(s.visible.isEmpty)
    }
    @Test func snoozeHidesUntilDue() {
        let s = NotificationStore(state: PersistedState(), now: { self.t0 })
        s.ingest([n("a")])
        s.snooze("a", .min10)
        #expect(s.visible.isEmpty)
        s.tick()
        #expect(s.visible.isEmpty)
    }
    @Test func tickResurfacesAtTop() {
        let c = Clock(t0)
        let s = NotificationStore(state: PersistedState(), now: { c.now })
        s.ingest([n("a"), n("b", at: 5)])
        s.snooze("a", .min10)
        c.now = t0.addingTimeInterval(601)
        s.tick()
        #expect(s.visible.map(\.id) == ["a", "b"])
        #expect(s.visible[0].surfacedAt == c.now)
        #expect(s.visible[0].snoozedUntil == nil)
    }
    @Test func ingestingKnownIdIsIgnored() {
        var st = PersistedState()
        st.handledIDs = ["old"]
        let s = NotificationStore(state: st, now: { self.t0 })
        s.ingest([n("old"), n("a")])
        #expect(s.visible.map(\.id) == ["a"])
        s.ingest([n("a", at: 50)])
        #expect(s.visible.count == 1 && s.visible[0].surfacedAt == t0)
        s.snooze("a", .hour1)
        s.ingest([n("a", at: 60)])
        #expect(s.visible.isEmpty)
    }
    @Test func overdueSnoozeResurfacesOnLoad() {
        var item = n("a")
        item.snoozedUntil = t0.addingTimeInterval(-60)
        var st = PersistedState()
        st.notifications = [n("b", at: -100), item]
        let s = NotificationStore(state: st, now: { self.t0 })
        #expect(s.visible.map(\.id) == ["a", "b"])
        #expect(s.visible[0].surfacedAt == t0)
    }
    @Test func handledIDsCapped() {
        let s = NotificationStore(state: PersistedState(), now: { self.t0 })
        for i in 0..<5002 { s.ingest([n("i\(i)")]); s.markDone("i\(i)") }
        var out = PersistedState()
        s.exportState(into: &out)
        #expect(out.handledIDs.count == 5000)
        #expect(!out.handledIDs.contains("i0") && out.handledIDs.contains("i5001"))
    }
    @Test func persistenceRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let p = Persistence(url: dir.appendingPathComponent("sub/state.json"))
        #expect(p.load().notifications.isEmpty)
        var st = PersistedState()
        st.notifications = [n("a")]
        st.handledIDs = ["x"]
        st.teamsLastSeen = ["c": "m"]
        st.deltaLinks = ["mail": URL(string: "https://e.com/d")!]
        st.settings.clientID = "cid"
        st.dock = DockPlacement(screenID: 1, edge: .left)
        p.save(st)
        let back = p.load()
        #expect(back.notifications == st.notifications)
        #expect(back.handledIDs == ["x"])
        #expect(back.teamsLastSeen == ["c": "m"])
        #expect(back.deltaLinks == st.deltaLinks)
        #expect(back.settings.clientID == "cid")
        #expect(back.dock == st.dock)
    }
    @Test func decodesMissingKeysWithDefaults() throws {
        let st = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        #expect(st.settings.tenantID == "organizations" && st.notifications.isEmpty)
    }
}
