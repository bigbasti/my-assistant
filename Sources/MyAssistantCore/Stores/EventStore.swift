import Foundation
import Observation

@Observable @MainActor
public final class EventStore {
    private var events: [CalendarEvent] = []
    private var dismissed: Set<String>
    @ObservationIgnored private var toned = Set<String>()
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored public var onChange: (() -> Void)?

    public init(state: PersistedState, now: @escaping () -> Date, calendar: Calendar = .autoupdatingCurrent) {
        self.dismissed = state.dismissedEventIDs
        self.now = now
        self.calendar = calendar
    }

    private var startOfTomorrow: Date {
        CalendarMapping.dayRange(now: now(), calendar: calendar).end
    }

    public var today: [CalendarEvent] {
        let t = now(), cutoff = startOfTomorrow
        return visible.filter { $0.end > t && $0.start < cutoff }
    }

    public var tomorrow: [CalendarEvent] {
        let range = CalendarMapping.dayRange(now: startOfTomorrow, calendar: calendar)
        return visible.filter { $0.start >= range.start && $0.start < range.end }
    }

    private var visible: [CalendarEvent] {
        events.filter { !$0.isAllDay && !dismissed.contains($0.id) }.sorted { $0.start < $1.start }
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
