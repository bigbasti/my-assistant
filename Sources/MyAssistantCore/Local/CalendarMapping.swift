import Foundation

public struct EventSnapshot: Sendable {
    public var itemID: String
    public var externalID: String?
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?
    public var url: URL?
    public var organizer: String?
    public var canceled: Bool
    public var declinedByMe: Bool

    public init(itemID: String, externalID: String?, title: String, start: Date, end: Date, isAllDay: Bool,
                location: String?, notes: String?, url: URL?, organizer: String?, canceled: Bool, declinedByMe: Bool) {
        self.itemID = itemID; self.externalID = externalID; self.title = title; self.start = start; self.end = end
        self.isAllDay = isAllDay; self.location = location; self.notes = notes; self.url = url
        self.organizer = organizer; self.canceled = canceled; self.declinedByMe = declinedByMe
    }
}

public enum CalendarMapping {
    public static func dayRange(now: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: now)
        return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400))
    }

    private static func matches(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        switch true {
        case host == "teams.microsoft.com": return path.hasPrefix("/l/meetup-join/") || path.hasPrefix("/meet/")
        case host == "zoom.us" || host.hasSuffix(".zoom.us"): return path.hasPrefix("/j/")
        case host == "webex.com" || host.hasSuffix(".webex.com"): return true
        case host == "meet.google.com": return true
        default: return false
        }
    }

    public static func meetingLink(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, matches(url) { return url }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for text in [location, notes] {
            guard let text, !text.isEmpty, let detector else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for m in detector.matches(in: text, range: range) {
                if let u = m.url, matches(u) { return u }
            }
        }
        return nil
    }

    public static func map(_ s: EventSnapshot) -> CalendarEvent? {
        guard !s.canceled, !s.declinedByMe else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = s.itemID.addingPercentEncoding(withAllowedCharacters: allowed) ?? s.itemID
        return CalendarEvent(
            id: "\(s.externalID ?? s.itemID)@\(Int(s.start.timeIntervalSince1970))",
            subject: s.title, start: s.start, end: s.end, location: s.location, organizer: s.organizer,
            webLink: URL(string: "ical://ekevent/\(encoded)?method=show&options=more"),
            joinURL: meetingLink(url: s.url, location: s.location, notes: s.notes),
            isAllDay: s.isAllDay)
    }
}
