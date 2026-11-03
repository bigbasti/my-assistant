import Testing
import Foundation
import CoreGraphics
@testable import MyAssistantCore

private let fixNow = ISO8601DateFormatter().date(from: "2026-11-03T12:00:00Z")!

@MainActor @Suite struct FinalFixTests {
    @Test func mailFirstRunUsesFilterAndPageSizeHeader() async throws {
        let t = MockTransport([(200, #"{"value":[],"@odata.deltaLink":"https://graph.microsoft.com/v1.0/d?t=1"}"#, [:])])
        _ = try await MailSource(client: GraphClient(tokens: MockTokens(), transport: t), now: { fixNow }).fetchNew(deltaLink: nil)
        let r = t.requests[0]
        let u = r.url!.absoluteString
        #expect(u.contains("$filter=receivedDateTime+ge+2026-11-02T12:00:00Z"))
        #expect(u.contains("$select="))
        #expect(r.value(forHTTPHeaderField: "Prefer") == "odata.maxpagesize=50")
    }

    @Test func mailDeltaRequestAlsoSendsHeader() async throws {
        let t = MockTransport([(200, #"{"value":[],"@odata.deltaLink":"https://graph.microsoft.com/v1.0/d?t=1"}"#, [:])])
        _ = try await MailSource(client: GraphClient(tokens: MockTokens(), transport: t), now: { fixNow })
            .fetchNew(deltaLink: URL(string: "https://graph.microsoft.com/v1.0/d?t=0"))
        #expect(t.requests[0].url!.absoluteString == "https://graph.microsoft.com/v1.0/d?t=0")
        #expect(t.requests[0].value(forHTTPHeaderField: "Prefer") == "odata.maxpagesize=50")
    }

    @Test func trustDecision() {
        let s = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(ScreenReserver.shouldStartEnforcing(trusted: true, strip: s, enforcing: false))
        #expect(!ScreenReserver.shouldStartEnforcing(trusted: false, strip: s, enforcing: false))
        #expect(!ScreenReserver.shouldStartEnforcing(trusted: true, strip: nil, enforcing: false))
        #expect(!ScreenReserver.shouldStartEnforcing(trusted: true, strip: s, enforcing: true))
    }

    @Test func recheckWithoutStripDoesNothing() {
        var asked = 0
        let r = ScreenReserver(isTrusted: { asked += 1; return true })
        r.recheckTrust()
        #expect(asked == 0 && !r.isWatchingTrust)
    }

    func model() -> AppModel {
        var st = PersistedState()
        st.deltaLinks = ["mail": URL(string: "https://x/d")!]
        st.teamsLastSeen = ["c": "1"]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ff-\(UUID()).json")
        let m = AppModel(persistence: Persistence(url: url))
        m.state = st
        return m
    }

    @Test func accountChangeClearsSyncState() async {
        let m = model()
        let c = SettingsController(model: m, restartPoller: {}, dockTo: { _ in }, setReserving: { _ in },
                                   signOutHook: { _ in })
        await c.applyAccount(clientID: "client-2", tenantID: "organizations")
        #expect(m.state.deltaLinks.isEmpty && m.state.teamsLastSeen.isEmpty)
    }

    @Test func signOutClearsSyncState() async {
        let m = model()
        let c = SettingsController(model: m, restartPoller: {}, dockTo: { _ in }, setReserving: { _ in },
                                   signOutHook: { _ in })
        await c.signOut()
        #expect(m.state.deltaLinks.isEmpty && m.state.teamsLastSeen.isEmpty)
    }

    @Test func corruptStateIsQuarantined() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("state.json")
        try Data("{not json".utf8).write(to: url)
        let s = Persistence(url: url).load()
        #expect(s == PersistedState())
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(!names.contains("state.json"))
        let bad = names.filter { $0.hasPrefix("state.corrupt-") && $0.hasSuffix(".json") }
        #expect(bad.count == 1)
        #expect(try String(contentsOf: dir.appendingPathComponent(bad[0]), encoding: .utf8) == "{not json")
    }

    @Test func replacePrunesDismissedIDs() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        func ev(_ id: String) -> CalendarEvent { CalendarEvent(id: id, subject: id, start: t0, end: t0.addingTimeInterval(3600), isAllDay: false) }
        let s = EventStore(state: PersistedState(), now: { t0 })
        s.replace([ev("a"), ev("b")])
        s.dismiss("a"); s.dismiss("b")
        s.replace([ev("b")])
        var st = PersistedState()
        s.exportState(into: &st)
        #expect(st.dismissedEventIDs == ["b"])
    }

    @Test func tenantAndClientValidation() {
        for bad in ["..", ".", "a..b", "abc\n", "a b", ""] {
            #expect(throws: GraphError.self) { try OAuthRequests.validate(clientID: "c", tenantID: bad) }
            #expect(throws: GraphError.self) { try OAuthRequests.validate(clientID: bad, tenantID: "t") }
        }
        #expect(throws: Never.self) { try OAuthRequests.validate(clientID: "a.b-c", tenantID: "contoso.com") }
    }
}
