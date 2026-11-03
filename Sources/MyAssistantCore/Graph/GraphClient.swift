import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (d, resp) = try await data(for: r)
        guard let h = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (d, h)
    }
}

public protocol TokenProvider: Sendable {
    func accessToken(forceRefresh: Bool) async throws -> String
}

public enum GraphError: Error, Equatable {
    case unauthorized
    case throttled(retryAfter: TimeInterval)
    case http(Int)
    case consentRequired
    case signedOut
}

public struct GraphClient: Sendable {
    public static let base = "https://graph.microsoft.com/v1.0"
    let tokens: TokenProvider
    let transport: HTTPTransport

    public init(tokens: TokenProvider, transport: HTTPTransport) {
        self.tokens = tokens
        self.transport = transport
    }

    func url(for urlOrPath: String) throws -> URL {
        let s = urlOrPath.hasPrefix("http") ? urlOrPath : Self.base + urlOrPath
        guard let u = URL(string: s) else { throw URLError(.badURL) }
        return u
    }

    func rawGet(_ urlOrPath: String, headers: [String: String]) async throws -> Data {
        let url = try url(for: urlOrPath)
        var refreshed = false
        while true {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(try await tokens.accessToken(forceRefresh: refreshed))", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            let (data, resp) = try await transport.send(req)
            switch resp.statusCode {
            case 200..<300: return data
            case 401:
                if refreshed { throw GraphError.unauthorized }
                refreshed = true
            case 403: throw GraphError.consentRequired
            case 429, 503:
                if let ra = resp.value(forHTTPHeaderField: "Retry-After"), let secs = TimeInterval(ra) {
                    throw GraphError.throttled(retryAfter: secs)
                }
                throw GraphError.http(resp.statusCode)
            default: throw GraphError.http(resp.statusCode)
            }
        }
    }

    public func get<T: Decodable>(_ urlOrPath: String, as: T.Type, headers: [String: String] = [:]) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await rawGet(urlOrPath, headers: headers))
    }

    private struct DeltaPage<T: Decodable>: Decodable {
        let value: [T]
        let next: String?
        let delta: String?
        enum CodingKeys: String, CodingKey {
            case value
            case next = "@odata.nextLink"
            case delta = "@odata.deltaLink"
        }
    }

    public func delta<T: Decodable>(start: String, deltaLink: URL?, headers: [String: String] = [:]) async throws -> (items: [T], deltaLink: URL) {
        var next = deltaLink?.absoluteString ?? start
        var items: [T] = []
        var restarted = deltaLink == nil
        while true {
            let data: Data
            do {
                data = try await rawGet(next, headers: headers)
            } catch GraphError.http(410) where !restarted {
                restarted = true
                items = []
                next = start
                continue
            }
            let page = try JSONDecoder().decode(DeltaPage<T>.self, from: data)
            items += page.value
            if let n = page.next { next = n; continue }
            guard let d = page.delta, let link = URL(string: d) else { throw GraphError.http(502) }
            return (items, link)
        }
    }
}
