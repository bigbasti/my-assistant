import Foundation
import CryptoKit
import AuthenticationServices
import AppKit

public enum PKCE {
    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public static func verifier() -> String {
        base64url(Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
    }
    public static func challenge(for verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}

public struct TokenSet: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
}

public enum OAuthRequests {
    public static let scopes = "offline_access User.Read Mail.Read Calendars.Read Chat.Read"
    public static let redirect = "myassistant://auth"

    static func endpoint(_ tenant: String, _ name: String) -> URL {
        URL(string: "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/\(name)")!
    }

    public static func authorizeURL(clientID: String, tenantID: String, challenge: String, state: String) -> URL {
        var c = URLComponents(url: endpoint(tenantID, "authorize"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_mode", value: "query"),
            .init(name: "scope", value: scopes),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        return c.url!
    }

    static func form(_ url: URL, _ fields: [(String, String)]) -> URLRequest {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = Data(fields.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
        return r
    }

    public static func exchange(clientID: String, tenantID: String, code: String, verifier: String) -> URLRequest {
        form(endpoint(tenantID, "token"), [
            ("client_id", clientID), ("grant_type", "authorization_code"), ("code", code),
            ("redirect_uri", redirect), ("code_verifier", verifier), ("scope", scopes),
        ])
    }

    public static func refresh(clientID: String, tenantID: String, refreshToken: String) -> URLRequest {
        form(endpoint(tenantID, "token"), [
            ("client_id", clientID), ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken), ("scope", scopes),
        ])
    }

    public static func parseTokens(_ data: Data, now: Date) throws -> TokenSet {
        struct R: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double }
        let r = try JSONDecoder().decode(R.self, from: data)
        return TokenSet(accessToken: r.access_token, refreshToken: r.refresh_token, expiresAt: now.addingTimeInterval(r.expires_in))
    }
}

public actor OAuth: TokenProvider {
    static let account = "refresh_token"
    private let clientID: String
    private let tenantID: String
    private let transport: HTTPTransport
    private let store: SecretStore
    private var cached: TokenSet?
    private var inFlight: Task<TokenSet, Error>?

    public init(clientID: String, tenantID: String, transport: HTTPTransport, store: SecretStore = KeychainSecretStore()) {
        self.clientID = clientID
        self.tenantID = tenantID
        self.transport = transport
        self.store = store
    }

    public func accessToken(forceRefresh: Bool) async throws -> String {
        if !forceRefresh, let c = cached, c.expiresAt.timeIntervalSinceNow > 60 { return c.accessToken }
        if let t = inFlight { return try await t.value.accessToken }
        guard let rt = store.get(account: Self.account) else { throw GraphError.signedOut }
        let req = OAuthRequests.refresh(clientID: clientID, tenantID: tenantID, refreshToken: rt)
        let transport = self.transport
        let task = Task { try await Self.run(req, transport) }
        inFlight = task
        defer { inFlight = nil }
        let t = try await task.value
        accept(t)
        return t.accessToken
    }

    private static func run(_ req: URLRequest, _ transport: HTTPTransport) async throws -> TokenSet {
        let (data, resp) = try await transport.send(req)
        guard (200..<300).contains(resp.statusCode) else {
            throw resp.statusCode == 400 || resp.statusCode == 401 ? GraphError.unauthorized : GraphError.http(resp.statusCode)
        }
        return try OAuthRequests.parseTokens(data, now: Date())
    }

    private func accept(_ t: TokenSet) {
        cached = t
        if let r = t.refreshToken { store.set(r, account: Self.account) }
    }

    public func signIn() async throws {
        let verifier = PKCE.verifier()
        let state = PKCE.verifier()
        let url = OAuthRequests.authorizeURL(clientID: clientID, tenantID: tenantID, challenge: PKCE.challenge(for: verifier), state: state)
        let callback = try await AuthSessionRunner.run(url: url)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else { throw GraphError.unauthorized }
        let t = try await Self.run(OAuthRequests.exchange(clientID: clientID, tenantID: tenantID, code: code, verifier: verifier), transport)
        accept(t)
    }

    public func signOut() {
        cached = nil
        inFlight?.cancel()
        inFlight = nil
        store.delete(account: Self.account)
    }
}

@MainActor
private final class AuthSessionRunner: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private static var current: AuthSessionRunner?

    static func run(url: URL) async throws -> URL {
        let runner = AuthSessionRunner()
        current = runner
        defer { current = nil }
        return try await runner.start(url)
    }

    private func start(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "myassistant") { cb, err in
                if let cb { cont.resume(returning: cb) } else { cont.resume(throwing: err ?? GraphError.unauthorized) }
            }
            s.prefersEphemeralWebBrowserSession = false
            s.presentationContextProvider = self
            session = s
            if !s.start() { cont.resume(throwing: GraphError.unauthorized) }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSWindow() }
    }
}
