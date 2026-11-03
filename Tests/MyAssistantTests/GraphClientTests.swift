import Testing
import Foundation
@testable import MyAssistantCore

final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [(Int, String, [String: String])]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [(Int, String, [String: String])]) { queue = responses }
    func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (code, body, headers) = lock.withLock { requests.append(r); return queue.removeFirst() }
        let resp = HTTPURLResponse(url: r.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
        return (Data(body.utf8), resp)
    }
}

final class MockTokens: TokenProvider, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var forceFlags: [Bool] = []
    func accessToken(forceRefresh: Bool) async throws -> String {
        lock.withLock { forceFlags.append(forceRefresh) }
        return forceRefresh ? "fresh" : "stale"
    }
}

struct Item: Decodable, Equatable { let id: String }
struct Page: Decodable { let value: [Item] }

@Suite struct GraphClientTests {
    @Test func pkceChallengeIsS256OfVerifier() {
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let v = PKCE.verifier()
        #expect(v.count >= 43 && !v.contains("=") && !v.contains("+") && !v.contains("/"))
    }

    @Test func deltaFollowsNextLinksAndReturnsDeltaLink() async throws {
        let t = MockTransport([
            (200, #"{"value":[{"id":"1"}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/next?x=1"}"#, [:]),
            (200, #"{"value":[{"id":"2"}],"@odata.deltaLink":"https://graph.microsoft.com/v1.0/delta?t=9"}"#, [:]),
        ])
        let c = GraphClient(tokens: MockTokens(), transport: t)
        let r: (items: [Item], deltaLink: URL) = try await c.delta(start: "/me/messages/delta", deltaLink: nil)
        #expect(r.items == [Item(id: "1"), Item(id: "2")])
        #expect(r.deltaLink.absoluteString == "https://graph.microsoft.com/v1.0/delta?t=9")
        #expect(t.requests[0].url!.absoluteString == "https://graph.microsoft.com/v1.0/me/messages/delta")
        #expect(t.requests[1].url!.absoluteString == "https://graph.microsoft.com/v1.0/next?x=1")
        #expect(t.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer stale")
    }

    @Test func deltaRestartsOnGone() async throws {
        let t = MockTransport([
            (410, "{}", [:]),
            (200, #"{"value":[{"id":"1"}],"@odata.deltaLink":"https://graph.microsoft.com/v1.0/d"}"#, [:]),
        ])
        let c = GraphClient(tokens: MockTokens(), transport: t)
        let r: (items: [Item], deltaLink: URL) = try await c.delta(start: "/start", deltaLink: URL(string: "https://graph.microsoft.com/v1.0/old")!)
        #expect(r.items.count == 1)
        #expect(t.requests[1].url!.absoluteString == "https://graph.microsoft.com/v1.0/start")
    }

    @Test func unauthorizedTriggersRefreshThenSurfacesError() async {
        let tokens = MockTokens()
        let t = MockTransport([(401, "{}", [:]), (401, "{}", [:])])
        let c = GraphClient(tokens: tokens, transport: t)
        await #expect(throws: GraphError.unauthorized) { let _: Page = try await c.get("/me", as: Page.self) }
        #expect(tokens.forceFlags == [false, true])
        #expect(t.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer fresh")
    }

    @Test func unauthorizedThenSuccessRetries() async throws {
        let t = MockTransport([(401, "{}", [:]), (200, #"{"value":[]}"#, [:])])
        let c = GraphClient(tokens: MockTokens(), transport: t)
        let p: Page = try await c.get("/me", as: Page.self)
        #expect(p.value.isEmpty)
    }

    @Test func throttledParsesRetryAfter() async {
        let t = MockTransport([(429, "{}", ["Retry-After": "7"])])
        let c = GraphClient(tokens: MockTokens(), transport: t)
        await #expect(throws: GraphError.throttled(retryAfter: 7)) { let _: Page = try await c.get("/me", as: Page.self) }
    }

    @Test func forbiddenMapsToConsentRequired() async {
        let t = MockTransport([(403, "{}", [:])])
        let c = GraphClient(tokens: MockTokens(), transport: t)
        await #expect(throws: GraphError.consentRequired) { let _: Page = try await c.get("/me", as: Page.self) }
    }

    @Test func otherErrorsMapToHttpAndHeadersAreSent() async {
        let t = MockTransport([(500, "{}", [:])])
        let c = GraphClient(tokens: MockTokens(), transport: t)
        await #expect(throws: GraphError.http(500)) {
            let _: Page = try await c.get("/me", as: Page.self, headers: ["Prefer": "outlook.timezone=\"UTC\""])
        }
        #expect(t.requests[0].value(forHTTPHeaderField: "Prefer") == "outlook.timezone=\"UTC\"")
    }
}

@Suite struct OAuthTests {
    @Test func authorizeURLHasPKCEParams() throws {
        let u = OAuthRequests.authorizeURL(clientID: "cid", tenantID: "ten", challenge: "chal", state: "st")
        let items = URLComponents(url: u, resolvingAgainstBaseURL: false)!.queryItems!
        func v(_ n: String) -> String? { items.first { $0.name == n }?.value }
        #expect(u.absoluteString.hasPrefix("https://login.microsoftonline.com/ten/oauth2/v2.0/authorize"))
        #expect(v("code_challenge") == "chal" && v("code_challenge_method") == "S256")
        #expect(v("redirect_uri") == "myassistant://auth" && v("response_type") == "code")
        #expect(v("scope") == "offline_access User.Read Mail.Read Calendars.Read Chat.Read")
    }

    @Test func tokenRequestBuilders() {
        let ex = OAuthRequests.exchange(clientID: "cid", tenantID: "ten", code: "c0", verifier: "ver")
        #expect(ex.url!.absoluteString == "https://login.microsoftonline.com/ten/oauth2/v2.0/token")
        let body = String(data: ex.httpBody!, encoding: .utf8)!
        #expect(ex.httpMethod == "POST")
        #expect(body.contains("grant_type=authorization_code") && body.contains("code_verifier=ver") && body.contains("code=c0"))
        let rf = OAuthRequests.refresh(clientID: "cid", tenantID: "ten", refreshToken: "rt")
        let rb = String(data: rf.httpBody!, encoding: .utf8)!
        #expect(rb.contains("grant_type=refresh_token") && rb.contains("refresh_token=rt"))
    }

    @Test func parsesTokenResponse() throws {
        let t = try OAuthRequests.parseTokens(Data(#"{"access_token":"a","refresh_token":"r","expires_in":3600}"#.utf8), now: Date(timeIntervalSince1970: 0))
        #expect(t.accessToken == "a" && t.refreshToken == "r" && t.expiresAt == Date(timeIntervalSince1970: 3600))
    }

    @Test func signedOutWithoutRefreshToken() async {
        let o = OAuth(clientID: "c", tenantID: "t", transport: MockTransport([]), store: InMemorySecretStore())
        await #expect(throws: GraphError.signedOut) { _ = try await o.accessToken(forceRefresh: false) }
    }

    @Test func refreshesOnceForConcurrentCallsAndCaches() async throws {
        let store = InMemorySecretStore()
        store.set("rt", account: "refresh_token")
        let t = MockTransport([(200, #"{"access_token":"A","refresh_token":"R2","expires_in":3600}"#, [:])])
        let o = OAuth(clientID: "c", tenantID: "t", transport: t, store: store)
        async let a = o.accessToken(forceRefresh: false)
        async let b = o.accessToken(forceRefresh: false)
        let (x, y) = try await (a, b)
        #expect(x == "A" && y == "A")
        _ = try await o.accessToken(forceRefresh: false)
        #expect(t.requests.count == 1)
        #expect(store.get(account: "refresh_token") == "R2")
    }
}
