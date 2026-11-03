import Testing
import Foundation
@testable import MyAssistantCore

@Suite struct SnoozeOptionTests {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }
    func date(_ d: Int, _ h: Int, _ m: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    @Test func labelsMatchSpec() {
        #expect(SnoozeOption.presets.map(\.label) == ["in 10 Min", "in 30 Min", "in 1 Hour", "in 3 Hours", "Tomorrow"])
        #expect(SnoozeOption.custom(Date()).label == "Custom…")
    }
    @Test func min10AddsTenMinutes() {
        let now = date(3, 16, 0)
        #expect(SnoozeOption.min10.resurfaceDate(now: now, firstSurfacedAt: now, calendar: cal) == date(3, 16, 10))
    }
    @Test func hour3AddsThreeHours() {
        let now = date(3, 16, 0)
        #expect(SnoozeOption.hour3.resurfaceDate(now: now, firstSurfacedAt: now, calendar: cal) == date(3, 19, 0))
    }
    @Test func tomorrowKeepsOriginalTimeOfDay() {
        #expect(SnoozeOption.tomorrow.resurfaceDate(now: date(3, 16, 0), firstSurfacedAt: date(3, 9, 42), calendar: cal) == date(4, 9, 42))
    }
    @Test func customReturnsGivenDate() {
        let d = date(7, 8, 15)
        #expect(SnoozeOption.custom(d).resurfaceDate(now: date(3, 16, 0), firstSurfacedAt: date(3, 9, 42), calendar: cal) == d)
    }
}
