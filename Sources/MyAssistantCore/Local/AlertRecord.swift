import Foundation

public struct AlertRecord: Equatable, Sendable {
    public var uuidHex: String
    public var bundleID: String
    public var delivered: Date
    public var title: String?
    public var subtitle: String?
    public var body: String?
    public var category: String?
    public var archivedStrings: [String]

    public init(uuidHex: String, bundleID: String, delivered: Date, title: String?, subtitle: String?,
                body: String?, category: String?, archivedStrings: [String]) {
        self.uuidHex = uuidHex
        self.bundleID = bundleID
        self.delivered = delivered
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.category = category
        self.archivedStrings = archivedStrings
    }

    public static func parse(uuid: Data, bundleID: String, deliveredRef: Double, data: Data) -> AlertRecord? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let req = root["req"] as? [String: Any] else { return nil }
        var strings: [String] = []
        if let usda = req["usda"] as? Data,
           let archive = try? PropertyListSerialization.propertyList(from: usda, options: [], format: nil) as? [String: Any],
           let objects = archive["$objects"] as? [Any] {
            strings = objects.compactMap { $0 as? String }
        }
        return AlertRecord(
            uuidHex: uuid.map { String(format: "%02x", $0) }.joined(),
            bundleID: bundleID,
            delivered: Date(timeIntervalSinceReferenceDate: deliveredRef),
            title: req["titl"] as? String,
            subtitle: req["subt"] as? String,
            body: req["body"] as? String,
            category: req["cate"] as? String,
            archivedStrings: strings)
    }
}
