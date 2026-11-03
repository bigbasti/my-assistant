import Testing
import Foundation
@testable import MyAssistantCore

@MainActor @Suite struct TomorrowTests {
    static var berlin: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }
    // 2026-11-03 15:00 Berlin
    let now = Self.berlin.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 15))!

    func at(day: Int, hour: Int) -> Date { Self.berlin.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))! }
    func ev(_ id: String, day: Int, hour: Int) -> CalendarEvent {
        CalendarEvent(id: id, subject: id, start: at(day: day, hour: hour), end: at(day: day, hour: hour).addingTimeInterval(1800))
    }
    func store() -> EventStore {
        let n = now
        return EventStore(state: PersistedState(), now: { n }, calendar: Self.berlin)
    }

    @Test func todayExcludesTomorrow() {
        let s = store()
        s.replace([ev("t1", day: 3, hour: 16), ev("m1", day: 4, hour: 9)])
        #expect(s.today.map(\.id) == ["t1"])
    }

    @Test func tomorrowListsNextDayOnlySorted() {
        let s = store()
        s.replace([ev("m2", day: 4, hour: 11), ev("m1", day: 4, hour: 9), ev("t1", day: 3, hour: 16), ev("x", day: 5, hour: 9)])
        #expect(s.tomorrow.map(\.id) == ["m1", "m2"])
    }

    @Test func dismissedTomorrowHidden() {
        let s = store()
        s.replace([ev("m1", day: 4, hour: 9), ev("m2", day: 4, hour: 10)])
        s.dismiss("m1")
        #expect(s.tomorrow.map(\.id) == ["m2"])
    }

    @Test func readRangeCoversTodayAndTomorrow() {
        let r = CalendarMapping.readRange(now: now, calendar: Self.berlin)
        #expect(r.start == at(day: 3, hour: 0))
        #expect(r.end == at(day: 5, hour: 0))
    }
}
