import Foundation
import Observation
import AppKit

@Observable @MainActor
public final class AppModel {
    @ObservationIgnored public let persistence: Persistence
    public var state: PersistedState
    public let notifications: NotificationStore
    public let events: EventStore
    public let todos: TodoStore
    public var status: [SourceKind: SourceStatus] = [:]
    @ObservationIgnored public var playTone: @MainActor () -> Void = { AppModel.playChime() }
    @ObservationIgnored public var opener: @MainActor (URL?) -> Void = { Opener.open($0) }
    @ObservationIgnored public var launchApp: @MainActor (String) -> Void = { AppModel.launch(bundleID: $0) }
    @ObservationIgnored public var mailDeleter: MailDeleting = AppleMailDeleter()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let clock: () -> Date
    /// Bumped every tick so views depending on time re-evaluate.
    public private(set) var tickCount = 0

    public var settings: AppSettings {
        get { state.settings }
        set { state.settings = newValue }
    }

    public init(persistence: Persistence,
                now: @escaping () -> Date = { Date() }) {
        self.persistence = persistence
        self.clock = now
        let s = persistence.load()
        self.state = s
        notifications = NotificationStore(state: s, now: now)
        events = EventStore(state: s, now: now)
        todos = TodoStore(state: s, now: now)
        notifications.onChange = { [weak self] in self?.save() }
        events.onChange = { [weak self] in self?.save() }
        todos.onChange = { [weak self] in self?.save() }
    }

    private func exported() -> PersistedState {
        var s = state
        notifications.exportState(into: &s)
        events.exportState(into: &s)
        todos.exportState(into: &s)
        state = s
        return s
    }

    public func open(_ url: URL?) { opener(url) }

    public func open(_ n: AssistantNotification) {
        if let url = n.openURL {
            // Cards saved before the chat-context fix carry Teams links without a query.
            if url.scheme == "msteams", url.query == nil,
               let fixed = URL(string: url.absoluteString + "?context=%7B%22contextType%22%3A%22chat%22%7D") {
                opener(fixed); return
            }
            opener(url); return
        }
        switch n.kind {
        case .mail: Task { await openMail(notificationQuery(n)) }
        case .teams: launchApp("com.microsoft.teams2")
        case .calendar: break
        }
    }

    /// Query identifying a mail card's message (shared by open and delete).
    public func notificationQuery(_ n: AssistantNotification) -> MailQuery {
        MailQuery(subject: n.title, sender: n.sender,
                  secondsAgo: max(0, Int(clock().timeIntervalSince(n.firstSurfacedAt).rounded())), toleranceSeconds: 300)
    }

    /// Opens the exact mail in Apple Mail; falls back to Outlook when it can't be found there.
    public func openMail(_ query: MailQuery) async {
        if case .found(let id) = await mailDeleter.messageID(for: query), let url = MailOpenResult.messageURL(for: id) {
            opener(url)
        } else {
            launchApp("com.microsoft.Outlook")
        }
    }

    /// Opens what a to-do was created from, exactly like clicking the original card.
    public func open(_ ref: TodoReference) {
        if ref.kind == .mail, ref.url == nil, let subject = ref.subject, let received = ref.received {
            let q = MailQuery(subject: subject, sender: ref.label,
                              secondsAgo: max(0, Int(clock().timeIntervalSince(received).rounded())), toleranceSeconds: 300)
            Task { await openMail(q) }
            return
        }
        switch ref.kind {
        case .calendar: open(ref.url)
        case .mail where ref.url == nil:
            // Older mail to-dos have no subject to search Apple Mail for.
            launchApp("com.microsoft.Outlook")
        case .teams, .mail:
            open(AssistantNotification(id: "ref", kind: ref.kind, title: "", sender: ref.label, preview: "",
                                       openURL: ref.url, firstSurfacedAt: clock(), surfacedAt: clock()))
        }
    }

    static func launch(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Deletes the real mail behind a mail card via Apple Mail; the card is removed only on success.
    @discardableResult
    public func deleteMail(_ n: AssistantNotification) async -> MailDeleteResult {
        let result = await mailDeleter.moveToTrash(notificationQuery(n))
        if result == .deleted { notifications.markDone(n.id) }
        return result
    }

    public func tick() {
        notifications.tick()
        let fired = events.tick(now: clock())
        if settings.playTone { for _ in fired { playTone() } }
        tickCount &+= 1
    }

    public func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stopTimer() { timer?.invalidate(); timer = nil }

    static func playChime() {
        let sound = Bundle.main.url(forResource: "chime", withExtension: "aiff")
            .flatMap { NSSound(contentsOf: $0, byReference: true) } ?? NSSound(named: "Glass")
        sound?.play()
    }

    public func injectSampleData() {
        let n = clock()
        func note(_ i: Int, _ k: SourceKind, _ sender: String, _ title: String, _ prev: String) -> AssistantNotification {
            let t = n.addingTimeInterval(Double(i))
            return AssistantNotification(id: "sample-\(UUID().uuidString)", kind: k, title: title, sender: sender,
                                         preview: prev, openURL: URL(string: "https://example.com"),
                                         firstSurfacedAt: t, surfacedAt: t)
        }
        notifications.ingest([
            note(0, .teams, "Anna Schmidt", "Sprint planning", "Can you join the chat? We need your input on the estimates for the next sprint."),
            note(1, .mail, "Ben Weber", "Quarterly report", "Please find attached the quarterly report. Let me know if anything is missing."),
            note(2, .mail, "Carla Meyer", "Lunch?", "Are you free for lunch today?"),
        ])
        let u = URL(string: "https://example.com")
        events.replace([12, 4, 0.5, -0.1].enumerated().map { i, m in
            let start = n.addingTimeInterval(m * 60)
            return CalendarEvent(id: "sample-ev-\(i)", subject: "Sample meeting \(i + 1)", start: start,
                                 end: start.addingTimeInterval(1800), location: "Room \(i + 1)",
                                 organizer: "Organizer \(i + 1)", webLink: u, joinURL: i % 2 == 0 ? u : nil)
        })
        tickCount &+= 1
    }

    public func save() { persistence.scheduleSave(exported()) }
    public func flush() { persistence.flush(exported()) }
}
