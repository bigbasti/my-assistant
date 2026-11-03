import Foundation
import os

public enum Diagnostics {
    private static let log = Logger(subsystem: "de.sebastiangross.MyAssistant", category: "diagnostics")

    /// Logs structure only (presence flags), never notification content.
    public static func dumpSources() {
        let bundles = ["com.microsoft.teams2", "com.microsoft.outlook"]
        do {
            let all = try NotificationDatabase().read(bundleIDs: bundles)
            for bundle in bundles {
                for r in all.filter({ $0.bundleID == bundle }).prefix(5) {
                    let hasConv = r.archivedStrings.contains { $0.contains("convId") || $0.hasPrefix("19:") }
                    let hasMsg = r.archivedStrings.contains { $0.contains("messageId") }
                    log.info("\(bundle, privacy: .public) cate=\(r.category ?? "nil", privacy: .public) titl=\(r.title != nil, privacy: .public) subt=\(r.subtitle != nil, privacy: .public) body=\(r.body != nil, privacy: .public) convId=\(hasConv, privacy: .public) messageId=\(hasMsg, privacy: .public)")
                }
            }
        } catch {
            log.error("notification db error: \(String(describing: error), privacy: .public)")
        }
    }
}
