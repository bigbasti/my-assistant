import Testing
import Foundation
@testable import MyAssistantCore

@Suite struct CalendarMappingTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func snap(id: String = "ABC/123", ext: String? = "EXT1", start: Date = start, url: URL? = nil,
                     location: String? = nil, notes: String? = nil,
                     canceled: Bool = false, declined: Bool = false) -> EventSnapshot {
        EventSnapshot(itemID: id, externalID: ext, title: "Sync", start: start, end: start.addingTimeInterval(1800),
                      isAllDay: false, location: location, notes: notes, url: url, organizer: "Anna",
                      canceled: canceled, declinedByMe: declined)
    }

    @Test func mapsBasicEvent() {
        let e = CalendarMapping.map(Self.snap())!
        #expect(e.id == "EXT1@1800000000")
        #expect(e.subject == "Sync")
        #expect(e.organizer == "Anna")
        #expect(e.webLink == URL(string: "ical://ekevent/ABC%2F123?method=show&options=more"))
    }

    @Test func teamsLinkFromNotes() {
        let link = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%7d"
        #expect(CalendarMapping.meetingLink(url: nil, location: nil, notes: "Join: \(link)\n") == URL(string: link))
    }

    @Test func urlFieldWinsOverNotes() {
        let u = URL(string: "https://zoom.us/j/111")!
        #expect(CalendarMapping.meetingLink(url: u, location: nil, notes: "https://meet.google.com/abc") == u)
    }

    @Test func zoomAndMeetLinks() {
        #expect(CalendarMapping.meetingLink(url: nil, location: "https://us02web.zoom.us/j/999", notes: nil)
                == URL(string: "https://us02web.zoom.us/j/999"))
        #expect(CalendarMapping.meetingLink(url: nil, location: nil, notes: "see https://meet.google.com/abc-defg")
                == URL(string: "https://meet.google.com/abc-defg"))
        #expect(CalendarMapping.meetingLink(url: nil, location: nil, notes: "https://acme.webex.com/meet/x")
                == URL(string: "https://acme.webex.com/meet/x"))
        #expect(CalendarMapping.meetingLink(url: nil, location: nil, notes: "https://teams.microsoft.com/meet/123")
                == URL(string: "https://teams.microsoft.com/meet/123"))
    }

    @Test func noLinkIsNil() {
        #expect(CalendarMapping.meetingLink(url: URL(string: "https://example.com/x"), location: "Room 4", notes: "https://example.com") == nil)
    }

    @Test func canceledAndDeclinedDropped() {
        #expect(CalendarMapping.map(Self.snap(canceled: true)) == nil)
        #expect(CalendarMapping.map(Self.snap(declined: true)) == nil)
    }

    @Test func recurringOccurrencesHaveDistinctIDs() {
        let a = CalendarMapping.map(Self.snap())!
        let b = CalendarMapping.map(Self.snap(start: Self.start.addingTimeInterval(86400)))!
        #expect(a.id != b.id)
    }

    @Test func dayRangeFollowsNow() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 0, minute: 1))!
        let r = CalendarMapping.dayRange(now: now, calendar: cal)
        #expect(r.start == cal.date(from: DateComponents(year: 2026, month: 11, day: 3))!)
        #expect(r.end == cal.date(from: DateComponents(year: 2026, month: 11, day: 4))!)
    }
}
