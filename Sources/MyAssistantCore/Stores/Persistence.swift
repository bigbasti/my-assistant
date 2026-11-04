import Foundation
import os

public struct AppSettings: Codable, Equatable, Sendable {
    public var enabled: Set<SourceKind> = Set(SourceKind.allCases)
    public var launchAtLogin = false
    public var reserveScreenSpace = true
    public var playTone = true
    /// 0 = fully see-through glass, 1 = nearly solid panel (for bright backgrounds).
    public var backgroundOpacity: Double = 0
    /// Keeps the panel (and its popovers) out of screen sharing and recordings.
    public var hideFromScreenSharing = true
    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Set<SourceKind>.self, forKey: .enabled) ?? Set(SourceKind.allCases)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        reserveScreenSpace = try c.decodeIfPresent(Bool.self, forKey: .reserveScreenSpace) ?? true
        playTone = try c.decodeIfPresent(Bool.self, forKey: .playTone) ?? true
        backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0
        hideFromScreenSharing = try c.decodeIfPresent(Bool.self, forKey: .hideFromScreenSharing) ?? true
    }
}

public struct PersistedState: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case notifications, handledIDs, handledOrder, dismissedEventIDs, dock, settings
        case bootstrappedSources, sourcesSeen, alertsBootstrapped
    }

    public var notifications: [AssistantNotification] = []
    public var handledIDs: Set<String> = []
    /// Insertion order of `handledIDs`, used to trim the oldest when capped.
    public var handledOrder: [String] = []
    public var dismissedEventIDs: Set<String> = []
    public var dock: DockPlacement?
    public var settings = AppSettings()
    public var bootstrappedSources: Set<SourceKind> = []
    public var sourcesSeen: Set<SourceKind> = []
    public init() {}

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(notifications, forKey: .notifications)
        try c.encode(handledIDs, forKey: .handledIDs)
        try c.encode(handledOrder, forKey: .handledOrder)
        try c.encode(dismissedEventIDs, forKey: .dismissedEventIDs)
        try c.encodeIfPresent(dock, forKey: .dock)
        try c.encode(settings, forKey: .settings)
        try c.encode(bootstrappedSources, forKey: .bootstrappedSources)
        try c.encode(sourcesSeen, forKey: .sourcesSeen)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notifications = try c.decodeIfPresent([AssistantNotification].self, forKey: .notifications) ?? []
        handledIDs = try c.decodeIfPresent(Set<String>.self, forKey: .handledIDs) ?? []
        handledOrder = try c.decodeIfPresent([String].self, forKey: .handledOrder) ?? []
        dismissedEventIDs = try c.decodeIfPresent(Set<String>.self, forKey: .dismissedEventIDs) ?? []
        dock = try c.decodeIfPresent(DockPlacement.self, forKey: .dock)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        if let set = try c.decodeIfPresent(Set<SourceKind>.self, forKey: .bootstrappedSources) {
            bootstrappedSources = set
        } else if try c.decodeIfPresent(Bool.self, forKey: .alertsBootstrapped) == true {
            bootstrappedSources = [.teams, .mail]
        }
        sourcesSeen = try c.decodeIfPresent(Set<SourceKind>.self, forKey: .sourcesSeen) ?? []
    }
}

public final class Persistence: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var pending: DispatchWorkItem?
    private var generation = 0
    private let queue = DispatchQueue(label: "MyAssistant.persistence")

    private static let log = Logger(subsystem: "de.sebastiangross.MyAssistant", category: "persistence")

    public init(url: URL) { self.url = url }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyAssistant/state.json")
    }

    public func load() -> PersistedState {
        guard let data = try? Data(contentsOf: url) else { return PersistedState() }
        do {
            return try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmmss"
            let dest = url.deletingLastPathComponent().appendingPathComponent("state.corrupt-\(f.string(from: Date())).json")
            do { try FileManager.default.moveItem(at: url, to: dest) }
            catch { Self.log.error("could not quarantine corrupt state: \(error.localizedDescription, privacy: .public)") }
            return PersistedState()
        }
    }

    public func save(_ state: PersistedState) {
        lock.lock(); defer { lock.unlock() }
        write(state)
    }

    private func write(_ state: PersistedState) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try enc.encode(state)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            Self.log.error("write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// True while a debounced save is waiting to run.
    public var hasPendingSave: Bool {
        lock.lock(); defer { lock.unlock() }
        return pending != nil
    }

    /// Debounced save (0.5 s); later calls replace the pending one.
    public func scheduleSave(_ state: PersistedState) {
        lock.lock()
        generation += 1
        let gen = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            guard self.generation == gen else { return }
            self.pending = nil
            self.write(state)
        }
        pending?.cancel()
        pending = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    /// Cancels any pending debounced save and writes `state` synchronously (call on quit).
    public func flush(_ state: PersistedState) {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        pending?.cancel()
        pending = nil
        write(state)
    }
}
