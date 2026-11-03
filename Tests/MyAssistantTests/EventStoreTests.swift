import Testing
import Foundation
@testable import MyAssistantCore

@MainActor @Suite struct EventStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func ev(_ id: String, start: TimeInterval, len: TimeInterval = 1800, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, subject: id, start: t0.addingTimeInterval(start), end: t0.addingTimeInterval(start + len), isAllDay: allDay)
    }
    func store(_ now: TimeInterval = 0) -> EventStore {
        EventStore(state: PersistedState(), now: { self.t0.addingTimeInterval(now) })
    }

    @Test func nextEventFirst() {
        let s = store()
        s.replace([ev("b", start: 900), ev("a", start: 300), ev("allday", start: 100, allDay: true)])
        #expect(s.today.map(\.id) == ["a", "b"])
    }
    @Test func endedEventsHidden() {
        let s = store(4000)
        s.replace([ev("old", start: 0), ev("new", start: 4300)])
        #expect(s.today.map(\.id) == ["new"])
    }
    @Test func dismissRemoves() {
        let s = store()
        var changed = 0
        s.onChange = { changed += 1 }
        s.replace([ev("a", start: 300)])
        s.dismiss("a")
        #expect(s.today.isEmpty)
        #expect(changed == 1)
        var st = PersistedState()
        s.exportState(into: &st)
        #expect(st.dismissedEventIDs == ["a"])
        let s2 = EventStore(state: st, now: { self.t0 })
        s2.replace([ev("a", start: 300)])
        #expect(s2.today.isEmpty)
    }
    @Test func toneFiresOnceAcrossRefreshes() {
        let s = store()
        s.replace([ev("a", start: 0)])
        #expect(s.tick(now: t0.addingTimeInterval(1)) == ["a"])
        s.replace([ev("a", start: 0)])
        #expect(s.tick(now: t0.addingTimeInterval(2)) == [])
    }
    @Test func rescheduledEventFiresAgain() {
        let s = store()
        s.replace([ev("a", start: 0)])
        #expect(s.tick(now: t0.addingTimeInterval(1)) == ["a"])
        s.replace([ev("a", start: 600)])
        #expect(s.tick(now: t0.addingTimeInterval(601)) == ["a"])
    }
    @Test func noToneForLongStartedEventOnLaunch() {
        let s = store(600)
        s.replace([ev("a", start: 0)])
        #expect(s.tick(now: t0.addingTimeInterval(600)) == [])
    }
    @Test func noToneBeforeStartOrDismissed() {
        let s = store()
        s.replace([ev("a", start: 30), ev("b", start: 0)])
        s.dismiss("b")
        #expect(s.tick(now: t0) == [])
    }
}
