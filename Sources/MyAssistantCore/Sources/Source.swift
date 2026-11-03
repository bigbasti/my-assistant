import Foundation

public enum SourceStatus: Equatable, Sendable {
    case disabled, signedOut, ok(Date), error(String), consentRequired
}

public protocol NotificationSource: Sendable {
    var kind: SourceKind { get }
    func fetchNew(deltaLink: URL?) async throws -> (items: [AssistantNotification], deltaLink: URL?)
}

public protocol SourceSet: Sendable {
    func fetchMail(deltaLink: URL?) async throws -> (items: [AssistantNotification], deltaLink: URL?)
    func fetchTeams(lastSeen: [String: String]) async throws -> (items: [AssistantNotification], lastSeen: [String: String])
    func fetchCalendar(now: Date) async throws -> [CalendarEvent]
}

public struct GraphSourceSet: SourceSet {
    let mail: MailSource, teams: TeamsSource, calendar: CalendarSource
    public init(client: GraphClient, now: @escaping @Sendable () -> Date = { Date() }) {
        mail = MailSource(client: client, now: now)
        teams = TeamsSource(client: client, now: now)
        calendar = CalendarSource(client: client)
    }
    public func fetchMail(deltaLink: URL?) async throws -> (items: [AssistantNotification], deltaLink: URL?) {
        try await mail.fetchNew(deltaLink: deltaLink)
    }
    public func fetchTeams(lastSeen: [String: String]) async throws -> (items: [AssistantNotification], lastSeen: [String: String]) {
        try await teams.fetchNew(lastSeen: lastSeen)
    }
    public func fetchCalendar(now: Date) async throws -> [CalendarEvent] { try await calendar.fetchToday(now: now) }
}

enum GraphDate {
    static func parse(_ s: String) -> Date? {
        let withZone = s.hasSuffix("Z") || s.contains("+") || s.range(of: #"-\d\d:\d\d$"#, options: .regularExpression) != nil
        let str = withZone ? s : s + "Z"
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: str) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: str) { return d }
        // Graph emits 7 fractional digits; trim to 3.
        if let r = str.range(of: #"\.\d+"#, options: .regularExpression) {
            let frac = String(str[r].prefix(4))
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: str.replacingCharacters(in: r, with: frac))
        }
        return nil
    }
}
