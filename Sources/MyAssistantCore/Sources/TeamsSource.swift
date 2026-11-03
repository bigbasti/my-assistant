import Foundation

public final class TeamsSource: @unchecked Sendable {
    let client: GraphClient
    let now: @Sendable () -> Date
    private let lock = NSLock()
    private var meID: String?

    public init(client: GraphClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client; self.now = now
    }

    struct Me: Decodable { let id: String }
    struct Chats: Decodable { let value: [Chat] }
    struct Chat: Decodable {
        struct Preview: Decodable {
            struct From: Decodable { struct User: Decodable { let id: String?; let displayName: String? }; let user: User? }
            struct Body: Decodable { let content: String? }
            let id: String
            let createdDateTime: String?
            let from: From?
            let body: Body?
        }
        let id: String
        let topic: String?
        let webUrl: String?
        let lastMessagePreview: Preview?
    }

    func currentUserID() async throws -> String {
        if let id = lock.withLock({ meID }) { return id }
        let me = try await client.get("/me?$select=id", as: Me.self)
        lock.withLock { meID = me.id }
        return me.id
    }

    public func fetchNew(lastSeen: [String: String]) async throws -> (items: [AssistantNotification], lastSeen: [String: String]) {
        let me = try await currentUserID()
        let chats = try await client.get(
            "/me/chats?$expand=lastMessagePreview&$orderby=lastMessagePreview/createdDateTime%20desc&$top=50",
            as: Chats.self).value
        let first = lastSeen.isEmpty
        var seen = lastSeen
        var out: [AssistantNotification] = []
        let t = now()
        for chat in chats {
            guard let p = chat.lastMessagePreview else { continue }
            let changed = lastSeen[chat.id] != p.id
            seen[chat.id] = p.id
            guard changed, !first else { continue }
            let from = p.from?.user
            guard from != nil, from?.id != me else { continue }
            let sender = from?.displayName ?? ""
            let url = chat.webUrl.flatMap(URL.init(string:)) ?? URL(string: "msteams:/l/chat/\(chat.id)/0")
            out.append(AssistantNotification(
                id: "teams:\(chat.id):\(p.id)", kind: .teams,
                title: chat.topic.flatMap { $0.isEmpty ? nil : $0 } ?? sender, sender: sender,
                preview: Self.plain(p.body?.content ?? ""), openURL: url,
                firstSurfacedAt: t, surfacedAt: p.createdDateTime.flatMap(GraphDate.parse) ?? t))
        }
        return (out, seen)
    }

    static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
