import Foundation
import AppKit

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
    private var wakeObserver: NSObjectProtocol?

    public init(model: AppModel, sources: SourceSet? = nil,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                now: @escaping () -> Date = { Date() }) {
        self.model = model; self.sources = sources; self.sleep = sleep; self.now = now
    }

    func resolveSources() -> SourceSet? {
        if let sources { return sources }
        guard let oauth = model.oauth else { return nil }
        return GraphSourceSet(client: GraphClient(tokens: oauth, transport: URLSession.shared))
    }

    public func start() {
        stop()
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
        guard let src = resolveSources() else { model.status[kind] = .signedOut; return Self.intervals[kind]! }
        do {
            switch kind {
            case .mail:
                let r = try await src.fetchMail(deltaLink: model.state.deltaLinks[kind.rawValue])
                model.notifications.ingest(r.items)
                if let l = r.deltaLink { model.state.deltaLinks[kind.rawValue] = l }
            case .teams:
                let r = try await src.fetchTeams(lastSeen: model.state.teamsLastSeen)
                model.notifications.ingest(r.items)
                model.state.teamsLastSeen = r.lastSeen
            case .calendar:
                model.events.replace(try await src.fetchCalendar(now: now()))
            }
            failures[kind] = 0
            model.status[kind] = .ok(now())
            model.save()
            return Self.interval(for: kind, now: now())
        } catch let e as GraphError {
            switch e {
            case .throttled(let s): model.status[kind] = .error("Throttled"); return max(1, s)
            case .consentRequired: model.status[kind] = .consentRequired
            case .signedOut: model.status[kind] = .signedOut
            case .unauthorized: model.status[kind] = .signedOut
            default: model.status[kind] = .error("\(e)")
            }
            return backoff(kind)
        } catch {
            model.status[kind] = .error(error.localizedDescription)
            return backoff(kind)
        }
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
