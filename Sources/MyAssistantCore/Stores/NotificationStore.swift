import Foundation
import Observation

@Observable @MainActor
public final class NotificationStore {
    public static let handledCap = 5000

    private var items: [AssistantNotification]
    private var handled: Set<String>
    private var handledOrder: [String]
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    /// Called after every mutation so the owner can schedule a save.
    @ObservationIgnored public var onChange: (() -> Void)?

    public init(state: PersistedState, now: @escaping () -> Date, calendar: Calendar = .current) {
        self.items = state.notifications
        self.now = now
        self.calendar = calendar
        var order = state.handledOrder.filter { state.handledIDs.contains($0) }
        let known = Set(order)
        order += state.handledIDs.subtracting(known).sorted()
        self.handledOrder = order
        self.handled = state.handledIDs
        resurfaceDue()
    }

    public var visible: [AssistantNotification] {
        items.filter { $0.snoozedUntil == nil }.sorted { $0.surfacedAt > $1.surfacedAt }
    }

    public func ingest(_ new: [AssistantNotification]) {
        var changed = false
        for item in new where !handled.contains(item.id) && !items.contains(where: { $0.id == item.id }) {
            items.append(item); changed = true
        }
        if changed { onChange?() }
    }

    public func markDone(_ id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        remember(id)
        onChange?()
    }

    public func snooze(_ id: String, _ option: SnoozeOption) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].snoozedUntil = option.resurfaceDate(now: now(), firstSurfacedAt: items[i].firstSurfacedAt, calendar: calendar)
        onChange?()
    }

    public func tick() {
        if resurfaceDue() { onChange?() }
    }

    public func exportState(into state: inout PersistedState) {
        state.notifications = items
        state.handledIDs = handled
        state.handledOrder = handledOrder
    }

    @discardableResult
    private func resurfaceDue() -> Bool {
        let t = now()
        var changed = false
        for i in items.indices {
            if let until = items[i].snoozedUntil, until <= t {
                items[i].snoozedUntil = nil
                items[i].surfacedAt = t
                changed = true
            }
        }
        return changed
    }

    private func remember(_ id: String) {
        guard handled.insert(id).inserted else { return }
        handledOrder.append(id)
        if handledOrder.count > Self.handledCap {
            let drop = handledOrder.count - Self.handledCap
            for old in handledOrder.prefix(drop) { handled.remove(old) }
            handledOrder.removeFirst(drop)
        }
    }
}
