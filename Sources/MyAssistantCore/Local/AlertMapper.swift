import Foundation

public enum AlertMapper {
    static let teamsBundle = "com.microsoft.teams2"
    static let outlookBundle = "com.microsoft.outlook"

    public static func map(_ r: AlertRecord) -> AssistantNotification? {
        switch r.bundleID {
        case teamsBundle:
            let ids = teamsIDs(r.archivedStrings)
            return AssistantNotification(
                id: "teams:\(ids.messageId ?? r.uuidHex)", kind: .teams, title: "Teams message",
                sender: r.title ?? "", preview: r.body ?? "",
                openURL: teamsURL(ids), firstSurfacedAt: r.delivered, surfacedAt: r.delivered)
        case outlookBundle:
            return AssistantNotification(
                id: "mail:\(r.uuidHex)", kind: .mail, title: r.title ?? "",
                sender: r.subtitle ?? "", preview: r.body ?? "",
                openURL: nil, firstSurfacedAt: r.delivered, surfacedAt: r.delivered)
        default:
            return nil
        }
    }

    public static func teamsIDs(_ strings: [String]) -> (convId: String?, messageId: String?) {
        var conv: String?
        var message: String?
        for s in strings {
            guard let data = s.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if conv == nil, let c = obj["convId"] as? String, !c.isEmpty { conv = c }
            if message == nil, let m = obj["messageId"] as? String, !m.isEmpty { message = m }
        }
        if conv == nil { conv = strings.first { $0.hasPrefix("19:") } }
        return (conv, message)
    }

    public static func isFresh(_ r: AlertRecord, now: Date) -> Bool {
        now.timeIntervalSince(r.delivered) <= 24 * 3600
    }

    private static func teamsURL(_ ids: (convId: String?, messageId: String?)) -> URL? {
        guard let conv = ids.convId else { return nil }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: ":@/")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        if let m = ids.messageId {
            return URL(string: "msteams:/l/message/\(enc(conv))/\(enc(m))")
        }
        return URL(string: "msteams:/l/chat/\(enc(conv))/0")
    }
}
