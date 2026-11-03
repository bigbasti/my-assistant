import Foundation
import EventKit

@MainActor
public final class CalendarReader {
    private let model: AppModel
    private let store: EKEventStore
    private let now: () -> Date
    private let calendar: Calendar
    private var generation = 0
    private var inFlight = false
    private var pending = false
    private var kickTask: Task<Void, Never>?
    private var zoneObservers: [NSObjectProtocol] = []
    private var observer: NSObjectProtocol?
    private var debounce: DispatchWorkItem?
    private var timer: DispatchSourceTimer?
    private var midnight: DispatchWorkItem?

    public init(model: AppModel, store: EKEventStore = .init(), now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.calendar = calendar
        self.model = model
        self.store = store
        self.now = now
    }

    public func start() {
        stop()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        for name in [Notification.Name.NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
            zoneObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.armMidnight(); self?.kick() }
            })
        }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 60, repeating: 60)
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.kick() }
        }
        t.resume()
        timer = t
        armMidnight()
        kick()
    }

    public func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        for o in zoneObservers { NotificationCenter.default.removeObserver(o) }
        zoneObservers = []
        generation += 1
        kickTask?.cancel(); kickTask = nil
        pending = false
        debounce?.cancel(); debounce = nil
        timer?.cancel(); timer = nil
        midnight?.cancel(); midnight = nil
    }

    private func scheduleRefresh() {
        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.kick() }
        }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
    }

    private func armMidnight() {
        midnight?.cancel()
        let date = now()
        let next = CalendarMapping.dayRange(now: date, calendar: calendar).end
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.kick()
                self.armMidnight()
            }
        }
        midnight = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, next.timeIntervalSince(date) + 1), execute: item)
    }

    public func refresh() async {
        if inFlight { pending = true; return }
        inFlight = true
        defer { inFlight = false }
        repeat {
            pending = false
            await refreshOnce()
        } while pending
    }

    private func refreshOnce() async {
        let gen = generation
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            do {
                let granted = try await store.requestFullAccessToEvents()
                guard gen == generation else { return }
                if granted { read() } else { model.status[.calendar] = .needsCalendarAccess }
            } catch {
                guard gen == generation else { return }
                model.status[.calendar] = .error("Calendar access request failed")
            }
        case .fullAccess:
            read()
        default:
            model.status[.calendar] = .needsCalendarAccess
        }
    }

    private func read() {
        let date = now()
        let range = CalendarMapping.dayRange(now: date, calendar: calendar)
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        let mapped = store.events(matching: predicate).compactMap { CalendarMapping.map(Self.snapshot($0)) }
            .sorted { $0.start < $1.start }
        model.events.replace(mapped)
        model.status[.calendar] = .ok(date)
    }

    nonisolated static func snapshot(_ ev: EKEvent) -> EventSnapshot {
        let declined = ev.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
        return EventSnapshot(
            itemID: ev.calendarItemIdentifier, externalID: ev.calendarItemExternalIdentifier,
            title: ev.title ?? "", start: ev.startDate, end: ev.endDate, isAllDay: ev.isAllDay,
            location: ev.location, notes: ev.notes, url: ev.url, organizer: ev.organizer?.name,
            canceled: ev.status == .canceled, declinedByMe: declined)
    }

    /// Presence flags only, never event content.
    public static func diagnostics(store: EKEventStore = .init(), now: Date = Date()) -> [String] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return ["calendar: no full access"] }
        let r = CalendarMapping.dayRange(now: now, calendar: .current)
        let events = store.events(matching: store.predicateForEvents(withStart: r.start, end: r.end, calendars: nil))
        var out = ["calendar events today: \(events.count)"]
        for ev in events {
            let s = snapshot(ev)
            let me = ev.attendees?.first { $0.isCurrentUser }
            out.append("url=\(s.url != nil) location=\(s.location != nil) notes=\(s.notes != nil) link=\(CalendarMapping.meetingLink(url: s.url, location: s.location, notes: s.notes) != nil) organizer=\(ev.organizer != nil) myStatus=\(me.map { String($0.participantStatus.rawValue) } ?? "none")")
        }
        return out
    }
}

extension CalendarReader {
    fileprivate func kick() {
        kickTask = Task { [weak self] in await self?.refresh() }
    }
}
