import Foundation

public struct CalendarEvent: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var subject: String
    public var start: Date
    public var end: Date
    public var location: String?
    public var organizer: String?
    public var webLink: URL?
    public var joinURL: URL?
    public var isAllDay: Bool

    public init(id: String, subject: String, start: Date, end: Date, location: String? = nil,
                organizer: String? = nil, webLink: URL? = nil, joinURL: URL? = nil, isAllDay: Bool = false) {
        self.id = id; self.subject = subject; self.start = start; self.end = end
        self.location = location; self.organizer = organizer; self.webLink = webLink
        self.joinURL = joinURL; self.isAllDay = isAllDay
    }
}
