import Foundation

public struct MailSource: NotificationSource {
    public let kind = SourceKind.mail
    let client: GraphClient
    let now: @Sendable () -> Date

    public init(client: GraphClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client; self.now = now
    }

    struct Message: Decodable {
        struct Addr: Decodable { struct E: Decodable { let name: String?; let address: String? }; let emailAddress: E? }
        struct Removed: Decodable {}
        let id: String
        let subject: String?
        let bodyPreview: String?
        let from: Addr?
        let webLink: String?
        let isRead: Bool?
        let receivedDateTime: String?
        let removed: Removed?
        enum CodingKeys: String, CodingKey {
            case id, subject, bodyPreview, from, webLink, isRead, receivedDateTime
            case removed = "@removed"
        }
    }

    public func fetchNew(deltaLink: URL?) async throws -> (items: [AssistantNotification], deltaLink: URL?) {
        let start = "/me/mailFolders/inbox/messages/delta?$select=subject,from,bodyPreview,webLink,isRead,receivedDateTime"
        let (msgs, link): ([Message], URL) = try await client.delta(start: start, deltaLink: deltaLink)
        let t = now()
        let cutoff = t.addingTimeInterval(-24 * 3600)
        let first = deltaLink == nil
        var out: [AssistantNotification] = []
        for m in msgs {
            if m.removed != nil || m.isRead == true { continue }
            let received = m.receivedDateTime.flatMap(GraphDate.parse)
            if first, let r = received, r < cutoff { continue }
            let sender = m.from?.emailAddress?.name ?? m.from?.emailAddress?.address ?? ""
            let preview = (m.bodyPreview ?? "").split(whereSeparator: \.isNewline).prefix(3).joined(separator: "\n")
            out.append(AssistantNotification(
                id: "mail:\(m.id)", kind: .mail, title: m.subject ?? "(no subject)", sender: sender,
                preview: preview, openURL: m.webLink.flatMap(URL.init(string:)),
                firstSurfacedAt: t, surfacedAt: received ?? t))
        }
        return (out, link)
    }
}
