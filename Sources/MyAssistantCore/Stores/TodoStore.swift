import Foundation
import Observation

@Observable @MainActor
public final class TodoStore {
    public private(set) var items: [TodoItem]
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored public var onChange: (() -> Void)?

    public init(state: PersistedState, now: @escaping () -> Date, calendar: Calendar = .autoupdatingCurrent) {
        self.items = state.todos
        self.now = now
        self.calendar = calendar
    }

    /// Due items first (soonest first), then the rest newest first.
    private static func ordered(_ list: [TodoItem]) -> [TodoItem] {
        list.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.createdAt > b.createdAt
            }
        }
    }

    private func isSnoozed(_ t: TodoItem, at date: Date) -> Bool {
        if let s = t.snoozedUntil { return s > date }
        return false
    }

    /// The collapsed view: open and not rescheduled into the future.
    public var visible: [TodoItem] {
        let n = now()
        return Self.ordered(items.filter { !$0.done && !isSnoozed($0, at: n) })
    }

    /// The expanded view: open, then rescheduled, then checked.
    public var all: [TodoItem] {
        let n = now()
        let open = items.filter { !$0.done && !isSnoozed($0, at: n) }
        let snoozed = items.filter { !$0.done && isSnoozed($0, at: n) }
        let done = items.filter(\.done)
        return Self.ordered(open) + Self.ordered(snoozed) + Self.ordered(done)
    }

    public func dueState(_ t: TodoItem) -> TodoItem.DueState {
        TodoItem.dueState(t.due, now: now(), calendar: calendar)
    }

    public func isSnoozed(_ t: TodoItem) -> Bool { isSnoozed(t, at: now()) }

    @discardableResult
    public func add(title: String, reference: TodoReference? = nil) -> UUID {
        // Distinct timestamps keep "newest first" stable for items created in the same instant.
        let created = max(now(), (items.map(\.createdAt).max() ?? .distantPast).addingTimeInterval(0.001))
        let item = TodoItem(title: title, createdAt: created, reference: reference)
        items.append(item)
        onChange?()
        return item.id
    }

    @discardableResult
    public func add(from n: AssistantNotification) -> UUID {
        let title = n.kind == .teams ? n.preview : n.title
        return add(title: title.isEmpty ? n.title : title,
                   reference: TodoReference(kind: n.kind, url: n.openURL, label: n.sender))
    }

    @discardableResult
    public func add(from e: CalendarEvent) -> UUID {
        add(title: e.subject, reference: TodoReference(kind: .calendar, url: e.webLink, label: e.subject))
    }

    private func update(_ id: UUID, _ change: (inout TodoItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        onChange?()
    }

    public func toggleDone(_ id: UUID) { update(id) { $0.done.toggle() } }
    public func rename(_ id: UUID, _ title: String) { update(id) { $0.title = title } }
    public func setNote(_ id: UUID, _ note: AttributedString) { update(id) { $0.note = note } }
    public func setDue(_ id: UUID, _ due: Date?) { update(id) { $0.due = due } }

    public func reschedule(_ id: UUID, _ option: SnoozeOption) {
        let n = now()
        update(id) { $0.snoozedUntil = option.resurfaceDate(now: n, firstSurfacedAt: n, calendar: calendar) }
    }

    public func clearReschedule(_ id: UUID) { update(id) { $0.snoozedUntil = nil } }

    public func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        onChange?()
    }

    public func exportState(into state: inout PersistedState) { state.todos = items }
}
