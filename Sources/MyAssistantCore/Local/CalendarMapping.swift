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

    private static func resolve(_ url: URL) -> URL? {
        if matches(url) { return url }
        guard let host = url.host?.lowercased(), host.hasSuffix("safelinks.protection.outlook.com"),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let inner = items.first(where: { $0.name == "url" })?.value,
              let u = URL(string: inner), matches(u) else { return nil }
        return u
    }

    private static let wrapped = try? NSRegularExpression(pattern: #"(https?://teams\.microsoft\.com/\S*)[ \t]*\r?\n(\S+)"#)
    private static let completeTeams = try? NSRegularExpression(pattern: #"^https?://teams\.microsoft\.com/(l/meetup-join/[^/\s]+/[^/\s]+|meet/\S+)"#)

    /// Removes angle brackets and re-joins a Teams URL that was hard-wrapped before it was complete.
    static func normalise(_ text: String) -> String {
        var t = text.replacingOccurrences(of: "<", with: " ").replacingOccurrences(of: ">", with: " ")
        guard let wrapped, let completeTeams else { return t }
        let ns = t as NSString
        for m in wrapped.matches(in: t, range: NSRange(location: 0, length: ns.length)).reversed() {
            let head = ns.substring(with: m.range(at: 1))
            let headRange = NSRange(location: 0, length: (head as NSString).length)
            if completeTeams.firstMatch(in: head, range: headRange) != nil { continue }
            let joined = head + ns.substring(with: m.range(at: 2))
            t = (t as NSString).replacingCharacters(in: m.range, with: joined)
        }
        return t
    }

    public static func meetingLink(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, let u = resolve(url) { return u }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for text in [location, notes] {
            guard let text, !text.isEmpty, let detector else { continue }
            let clean = normalise(text)
            let range = NSRange(location: 0, length: (clean as NSString).length)
            for m in detector.matches(in: clean, range: range) {
                if let u = m.url, let r = resolve(u) { return r }
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
