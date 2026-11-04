import Foundation

/// An app or process the assistant keeps running.
public struct WatchedItem: Codable, Equatable, Identifiable, Sendable {
    public enum Target: Codable, Equatable, Sendable {
        /// An app bundle; restarted via Launch Services without stealing focus.
        case app(bundleID: String?, path: String)
        /// A plain executable; relaunched with the same arguments, detached from the assistant.
        case process(path: String, arguments: [String])
    }

    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var target: Target

    public init(id: UUID = UUID(), name: String, enabled: Bool = true, target: Target) {
        self.id = id; self.name = name; self.enabled = enabled; self.target = target
    }

    /// Builds an item for an app bundle on disk (e.g. picked from /Applications).
    public static func app(at url: URL) -> WatchedItem {
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return WatchedItem(name: name, target: .app(bundleID: bundle?.bundleIdentifier, path: url.path))
    }
}

public enum KeeperStatus: Equatable, Sendable {
    case off, running, restarted(Date), paused, failed(String)
}
