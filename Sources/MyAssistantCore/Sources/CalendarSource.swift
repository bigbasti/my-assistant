import Foundation

public struct CalendarSource: Sendable {
    let client: GraphClient
    public init(client: GraphClient) { self.client = client }

    struct Page: Decodable { let value: [Ev] }
    struct Ev: Decodable {
        struct When: Decodable { let dateTime: String }
        struct Loc: Decodable { let displayName: String? }
        struct Org: Decodable { struct E: Decodable { let name: String? }; let emailAddress: E? }
        struct Meeting: Decodable { let joinUrl: String? }
        let id: String
        let subject: String?
        let start: When
        let end: When
        let location: Loc?
        let organizer: Org?
        let webLink: String?
        let onlineMeeting: Meeting?
        let isAllDay: Bool?
        let isCancelled: Bool?
    }

    public func fetchToday(now: Date) async throws -> [CalendarEvent] {
        let cal = Calendar.current
        let s = cal.startOfDay(for: now)
        let e = cal.date(byAdding: .day, value: 1, to: s)!
        let f = ISO8601DateFormatter()
        let sel = "subject,start,end,location,organizer,webLink,onlineMeeting,isAllDay,isCancelled"
        let path = "/me/calendarView?startDateTime=\(f.string(from: s))&endDateTime=\(f.string(from: e))&$select=\(sel)&$orderby=start/dateTime&$top=50"
        let page = try await client.get(path, as: Page.self, headers: ["Prefer": #"outlook.timezone="UTC""#])
        return page.value.compactMap { ev in
            if ev.isCancelled == true { return nil }
            guard let st = GraphDate.parse(ev.start.dateTime), let en = GraphDate.parse(ev.end.dateTime) else { return nil }
            let loc = ev.location?.displayName.flatMap { $0.isEmpty ? nil : $0 }
            return CalendarEvent(
                id: ev.id, subject: ev.subject ?? "(no title)", start: st, end: en, location: loc,
                organizer: ev.organizer?.emailAddress?.name, webLink: ev.webLink.flatMap(URL.init(string:)),
                joinURL: ev.onlineMeeting?.joinUrl.flatMap(URL.init(string:)), isAllDay: ev.isAllDay ?? false)
        }.sorted { $0.start < $1.start }
    }
}
