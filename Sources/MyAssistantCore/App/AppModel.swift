import Foundation
import Observation

@Observable @MainActor
public final class AppModel {
    @ObservationIgnored public let persistence: Persistence
    public var state: PersistedState
    public let notifications: NotificationStore
    public let events: EventStore
    public var status: [SourceKind: SourceStatus] = [:]
    @ObservationIgnored public private(set) var oauth: OAuth?

    public var settings: AppSettings {
        get { state.settings }
        set { state.settings = newValue }
    }

    public init(persistence: Persistence, transport: HTTPTransport = URLSession.shared,
                now: @escaping () -> Date = { Date() }) {
        self.persistence = persistence
        let s = persistence.load()
        self.state = s
        notifications = NotificationStore(state: s, now: now)
        events = EventStore(state: s, now: now)
        rebuildOAuth(transport: transport)
        notifications.onChange = { [weak self] in self?.save() }
        events.onChange = { [weak self] in self?.save() }
    }

    public func rebuildOAuth(transport: HTTPTransport = URLSession.shared) {
        let s = state.settings
        oauth = s.clientID.isEmpty ? nil : OAuth(clientID: s.clientID, tenantID: s.tenantID, transport: transport)
    }

    private func exported() -> PersistedState {
        var s = state
        notifications.exportState(into: &s)
        events.exportState(into: &s)
        state = s
        return s
    }

    public func save() { persistence.scheduleSave(exported()) }
    public func flush() { persistence.flush(exported()) }
}
