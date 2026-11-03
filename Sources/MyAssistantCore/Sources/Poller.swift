import Foundation
import AppKit

public protocol NotificationSource: Sendable {
    var kind: SourceKind { get }
    func fetchNew(deltaLink: URL?) async throws -> (items: [AssistantNotification], deltaLink: URL?)
}

public protocol SourceSet: Sendable {
    func fetchMail(deltaLink: URL?) async throws -> (items: [AssistantNotification], deltaLink: URL?)
    func fetchTeams(lastSeen: [String: String]) async throws -> (items: [AssistantNotification], lastSeen: [String: String])
    func fetchCalendar(now: Date) async throws -> [CalendarEvent]
}

public struct GraphSourceSet: SourceSet {
    let mail: MailSource, teams: TeamsSource, calendar: CalendarSource
    public init(client: GraphClient, now: @escaping @Sendable () -> Date = { Date() }) {
        mail = MailSource(client: client, now: now)
        teams = TeamsSource(client: client, now: now)
        calendar = CalendarSource(client: client)
    }
    public func fetchMail(deltaLink: URL?) async throws -> (items: [AssistantNotification], deltaLink: URL?) {
        try await mail.fetchNew(deltaLink: deltaLink)
    }
    public func fetchTeams(lastSeen: [String: String]) async throws -> (items: [AssistantNotification], lastSeen: [String: String]) {
        try await teams.fetchNew(lastSeen: lastSeen)
    }
    public func fetchCalendar(now: Date) async throws -> [CalendarEvent] { try await calendar.fetchToday(now: now) }
}

enum GraphDate {
    static func parse(_ s: String) -> Date? {
        let withZone = s.hasSuffix("Z") || s.contains("+") || s.range(of: #"-\d\d:\d\d$"#, options: .regularExpression) != nil
        let str = withZone ? s : s + "Z"
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: str) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: str) { return d }
        // Graph emits 7 fractional digits; trim to 3.
        if let r = str.range(of: #"\.\d+"#, options: .regularExpression) {
            let frac = String(str[r].prefix(4))
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: str.replacingCharacters(in: r, with: frac))
        }
        return nil
    }
}


@MainActor
public final class Poller {
    public static let intervals: [SourceKind: TimeInterval] = [.mail: 30, .teams: 20, .calendar: 60]
    static let backoffBase: TimeInterval = 30
    static let backoffCap: TimeInterval = 300

    let model: AppModel
    let sources: SourceSet?
    let sleep: @Sendable (Duration) async throws -> Void
    let now: () -> Date
    private var tasks: [SourceKind: Task<Void, Never>] = [:]
    private var failures: [SourceKind: Int] = [:]
    let makeSources: @MainActor (OAuth) -> SourceSet
    private var cached: (oauth: OAuth, set: SourceSet)?
    private var wakeObserver: NSObjectProtocol?

    public init(model: AppModel, sources: SourceSet? = nil,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                now: @escaping () -> Date = { Date() },
                makeSources: @escaping @MainActor (OAuth) -> SourceSet = {
                    GraphSourceSet(client: GraphClient(tokens: $0, transport: URLSession.shared))
                }) {
        self.model = model; self.sources = sources; self.sleep = sleep; self.now = now
        self.makeSources = makeSources
    }

    func resolveSources() -> SourceSet? {
        if let sources { return sources }
        guard let oauth = model.oauth else { cached = nil; return nil }
        if let c = cached, c.oauth === oauth { return c.set }
        let set = makeSources(oauth)
        cached = (oauth, set)
        return set
    }

    public func start() {
        stop()
        failures = [:]
        cached = nil
        for kind in SourceKind.allCases {
            guard model.settings.enabled.contains(kind) else { model.status[kind] = .disabled; continue }
            tasks[kind] = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let delay = await self.pollOnce(kind)
                    try? await self.sleep(.seconds(delay))
                }
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
    }

    public func stop() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        if let o = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(o); wakeObserver = nil }
    }

    public func refreshNow() {
        guard !tasks.isEmpty else { return }
        start()
    }

    /// Polls one source once; returns the seconds to wait before the next poll.
    @discardableResult
    public func pollOnce(_ kind: SourceKind) async -> TimeInterval {
        guard model.settings.enabled.contains(kind) else { model.status[kind] = .disabled; return Self.intervals[kind]! }
        guard let src = resolveSources() else { model.status[kind] = .error("Signed out"); return Self.intervals[kind]! }
        do {
            switch kind {
            case .mail:
                let r = try await src.fetchMail(deltaLink: model.state.deltaLinks[kind.rawValue])
                try Task.checkCancellation()
                model.notifications.ingest(r.items)
                if let l = r.deltaLink { model.state.deltaLinks[kind.rawValue] = l }
            case .teams:
                let r = try await src.fetchTeams(lastSeen: model.state.teamsLastSeen)
                try Task.checkCancellation()
                model.notifications.ingest(r.items)
                model.state.teamsLastSeen = r.lastSeen
            case .calendar:
                let evs = try await src.fetchCalendar(now: now())
                try Task.checkCancellation()
                model.events.replace(evs)
            }
            failures[kind] = 0
            model.status[kind] = .ok(now())
            model.save()
            return Self.interval(for: kind, now: now())
        } catch where Self.isCancellation(error) || Task.isCancelled {
            return Self.interval(for: kind, now: now())
        } catch let e as GraphError {
            switch e {
            case .throttled(let s): model.status[kind] = .error("Throttled"); return max(1, s)
            case .consentRequired: model.status[kind] = .error("Consent required")
            case .signedOut: model.status[kind] = .error("Signed out")
            case .unauthorized: model.status[kind] = .error("Signed out")
            default: model.status[kind] = .error("\(e)")
            }
            return backoff(kind)
        } catch {
            model.status[kind] = .error(error.localizedDescription)
            return backoff(kind)
        }
    }

    static func isCancellation(_ e: Error) -> Bool {
        e is CancellationError || (e as? URLError)?.code == .cancelled
    }

    private func backoff(_ kind: SourceKind) -> TimeInterval {
        let n = failures[kind, default: 0]
        failures[kind] = n + 1
        return min(Self.backoffCap, Self.backoffBase * pow(2, Double(n)))
    }

    static func interval(for kind: SourceKind, now: Date, calendar: Calendar = .current) -> TimeInterval {
        let base = intervals[kind]!
        guard kind == .calendar,
              let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return base }
        return max(1, min(base, midnight.timeIntervalSince(now) + 1))
    }
}
