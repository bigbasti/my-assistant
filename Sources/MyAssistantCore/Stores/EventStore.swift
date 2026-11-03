import Foundation
import Observation

@Observable @MainActor
public final class EventStore {
    private var events: [CalendarEvent] = []
    private var dismissed: Set<String>
    @ObservationIgnored private var toned = Set<String>()
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored public var onChange: (() -> Void)?

    public init(state: PersistedState, now: @escaping () -> Date) {
        self.dismissed = state.dismissedEventIDs
        self.now = now
    }

    public var today: [CalendarEvent] {
        let t = now()
        return events
            .filter { !$0.isAllDay && !dismissed.contains($0.id) && $0.end > t }
            .sorted { $0.start < $1.start }
    }

    public func replace(_ new: [CalendarEvent]) {
        events = new
        let ids = Set(new.map(\.id))
        let kept = dismissed.intersection(ids)
        if kept != dismissed { dismissed = kept; onChange?() }
    }

    public func dismiss(_ id: String) {
        guard dismissed.insert(id).inserted else { return }
        onChange?()
    }

    /// IDs whose start tone should play now; once per id+start, only within 60 s after start.
    public func tick(now t: Date) -> [String] {
        var fire: [String] = []
        for e in events where !e.isAllDay && !dismissed.contains(e.id) {
            let since = t.timeIntervalSince(e.start)
            guard since >= 0, since <= 60 else { continue }
            if toned.insert("\(e.id)@\(e.start.timeIntervalSince1970)").inserted { fire.append(e.id) }
        }
        return fire
    }

    public func exportState(into state: inout PersistedState) {
        state.dismissedEventIDs = dismissed
    }
}
