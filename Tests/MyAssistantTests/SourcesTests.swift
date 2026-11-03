import Testing
import Foundation
@testable import MyAssistantCore

private func client(_ responses: [(Int, String, [String: String])]) -> (GraphClient, MockTransport) {
    let t = MockTransport(responses)
    return (GraphClient(tokens: MockTokens(), transport: t), t)
}
private let now = ISO8601DateFormatter().date(from: "2026-11-03T12:00:00Z")!
private let deltaTail = #","@odata.deltaLink":"https://graph.microsoft.com/v1.0/d?t=1"}"#

private let mailJSON = #"""
{"value":[
{"id":"m1","subject":"Hello","bodyPreview":"l1\nl2\nl3\nl4","from":{"emailAddress":{"name":"Ann","address":"a@x"}},"webLink":"https://outlook/m1","isRead":false,"receivedDateTime":"2026-11-03T11:00:00Z"},
{"id":"m2","subject":"Old","bodyPreview":"x","from":{"emailAddress":{"name":"Bob"}},"webLink":"https://outlook/m2","isRead":false,"receivedDateTime":"2026-11-01T11:00:00Z"},
{"id":"m3","subject":"Read","isRead":true,"receivedDateTime":"2026-11-03T11:00:00Z"},
{"id":"m4","@removed":{"reason":"deleted"}}]
"""# + deltaTail

private let chatsJSON = #"""
{"value":[
{"id":"c1","webUrl":"https://teams/c1","topic":"Proj","lastMessagePreview":{"id":"2","createdDateTime":"2026-11-03T11:59:00Z","from":{"user":{"id":"other","displayName":"Ann"}},"body":{"content":"<p>hi</p>"}}},
{"id":"c2","lastMessagePreview":{"id":"9","createdDateTime":"2026-11-03T11:58:00Z","from":{"user":{"id":"me1","displayName":"Me"}},"body":{"content":"mine"}}},
{"id":"c3","lastMessagePreview":{"id":"5","createdDateTime":"2026-11-03T11:57:00Z","from":{"user":{"id":"other","displayName":"Cy"}},"body":{"content":"same"}}}]}
"""#

@Suite struct SourcesTests {
    @Test func mailMapsSenderSubjectPreviewWebLink() async throws {
        let (c, _) = client([(200, mailJSON, [:])])
        let r = try await MailSource(client: c, now: { now }).fetchNew(deltaLink: URL(string: "https://graph.microsoft.com/v1.0/d?t=0"))
        #expect(r.items.map(\.id) == ["mail:m1", "mail:m2"])
        let n = r.items[0]
        #expect(n.id == "mail:m1" && n.title == "Hello" && n.sender == "Ann")
        #expect(n.preview == "l1\nl2\nl3")
        #expect(n.openURL?.absoluteString == "https://outlook/m1")
        #expect(r.deltaLink != nil)
    }

    @Test func mailFirstRunSkipsOlderThan24h() async throws {
        let (c, _) = client([(200, mailJSON, [:])])
        let r = try await MailSource(client: c, now: { now }).fetchNew(deltaLink: nil)
        #expect(r.items.map(\.id) == ["mail:m1"])
    }

    @Test func teamsEmitsOnlyChangedChatsNotFromMe() async throws {
        let (c, _) = client([(200, #"{"id":"me1"}"#, [:]), (200, chatsJSON, [:])])
        let r = try await TeamsSource(client: c, now: { now })
            .fetchNew(lastSeen: ["c1": "1", "c2": "8", "c3": "5"])
        #expect(r.items.count == 1)
        #expect(r.items[0].title == "Proj" && r.items[0].sender == "Ann" && r.items[0].preview == "hi")
        #expect(r.items[0].openURL?.absoluteString == "https://teams/c1")
        #expect(r.lastSeen == ["c1": "2", "c2": "9", "c3": "5"])
    }

    @Test func teamsFirstRunEmitsNothing() async throws {
        let (c, _) = client([(200, #"{"id":"me1"}"#, [:]), (200, chatsJSON, [:])])
        let r = try await TeamsSource(client: c, now: { now }).fetchNew(lastSeen: [:])
        #expect(r.items.isEmpty)
        #expect(r.lastSeen.count == 3)
    }

    private let calJSON = #"""
    {"value":[
    {"id":"e2","subject":"Cancelled","start":{"dateTime":"2026-11-03T15:00:00.0000000"},"end":{"dateTime":"2026-11-03T16:00:00.0000000"},"isCancelled":true},
    {"id":"e1","subject":"Sync","start":{"dateTime":"2026-11-03T13:00:00.0000000","timeZone":"UTC"},"end":{"dateTime":"2026-11-03T13:30:00.0000000"},"location":{"displayName":"Room"},"organizer":{"emailAddress":{"name":"Ann"}},"webLink":"https://outlook/e1","onlineMeeting":{"joinUrl":"https://teams.microsoft.com/l/meetup-join/x"},"isAllDay":false}]}
    """#

    @Test func calendarParsesUTCAndJoinURL() async throws {
        let (c, t) = client([(200, calJSON, [:])])
        let evs = try await CalendarSource(client: c).fetchToday(now: now)
        #expect(evs.count == 1)
        #expect(evs[0].start == ISO8601DateFormatter().date(from: "2026-11-03T13:00:00Z"))
        #expect(evs[0].joinURL?.absoluteString == "https://teams.microsoft.com/l/meetup-join/x")
        #expect(evs[0].location == "Room" && evs[0].organizer == "Ann")
        #expect(t.requests[0].value(forHTTPHeaderField: "Prefer") == #"outlook.timezone="UTC""#)
    }

    @Test func calendarDropsCancelled() async throws {
        let (c, _) = client([(200, calJSON, [:])])
        let evs = try await CalendarSource(client: c).fetchToday(now: now)
        #expect(!evs.contains { $0.id == "e2" })
    }
}

struct FakeSources: SourceSet {
    var mail: @Sendable (URL?) async throws -> (items: [AssistantNotification], deltaLink: URL?) = { _ in ([], nil) }
    func fetchMail(deltaLink: URL?) async throws -> (items: [AssistantNotification], deltaLink: URL?) { try await mail(deltaLink) }
    func fetchTeams(lastSeen: [String: String]) async throws -> (items: [AssistantNotification], lastSeen: [String: String]) { ([], lastSeen) }
    func fetchCalendar(now: Date) async throws -> [CalendarEvent] { [] }
}

@MainActor @Suite struct PollerTests {
    func model() -> AppModel {
        AppModel(persistence: Persistence(url: FileManager.default.temporaryDirectory.appendingPathComponent("p-\(UUID()).json")))
    }

    @Test func successStoresDeltaLinkAndStatus() async {
        let m = model()
        let link = URL(string: "https://graph.microsoft.com/v1.0/d?t=2")!
        var f = FakeSources(); f.mail = { _ in ([], link) }
        let p = Poller(model: m, sources: f, now: { now })
        let d = await p.pollOnce(.mail)
        #expect(d == 30)
        #expect(m.state.deltaLinks["mail"] == link)
        #expect(m.status[.mail] == .ok(now))
    }

    @Test func errorsBackOffAndThrottleHonored() async {
        let m = model()
        var f = FakeSources(); f.mail = { _ in throw GraphError.http(500) }
        let p = Poller(model: m, sources: f, now: { now })
        #expect(await p.pollOnce(.mail) == 30)
        #expect(await p.pollOnce(.mail) == 60)
        for _ in 0..<5 { _ = await p.pollOnce(.mail) }
        #expect(await p.pollOnce(.mail) == 300)
        var g = FakeSources(); g.mail = { _ in throw GraphError.throttled(retryAfter: 42) }
        #expect(await Poller(model: m, sources: g).pollOnce(.mail) == 42)
        var h = FakeSources(); h.mail = { _ in throw GraphError.consentRequired }
        _ = await Poller(model: m, sources: h).pollOnce(.mail)
        #expect(m.status[.mail] == .consentRequired)
    }

    @Test func noOAuthMeansSignedOut() async {
        let m = model()
        _ = await Poller(model: m).pollOnce(.teams)
        #expect(m.status[.teams] == .signedOut)
    }
}
