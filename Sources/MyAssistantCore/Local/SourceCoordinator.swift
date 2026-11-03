import Foundation
import AppKit

@MainActor
public final class SourceCoordinator {
    private let model: AppModel
    private let watcher: NotificationWatcher
    private let calendar: CalendarReader
    private var wakeObserver: NSObjectProtocol?

    public init(model: AppModel, watcher: NotificationWatcher, calendar: CalendarReader) {
        self.model = model
        self.watcher = watcher
        self.calendar = calendar
    }

    public func start() {
        stop()
        let enabled = model.settings.enabled
        for kind in SourceKind.allCases where !enabled.contains(kind) { model.status[kind] = .disabled }
        if enabled.contains(.teams) || enabled.contains(.mail) { watcher.start() }
        if enabled.contains(.calendar) { calendar.start() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        }
    }

    public func stop() {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        watcher.stop()
        calendar.stop()
    }

    public func restart() {
        stop()
        start()
    }

    private func didWake() {
        let enabled = model.settings.enabled
        if enabled.contains(.teams) || enabled.contains(.mail) { watcher.readNow() }
        if enabled.contains(.calendar) { Task { await calendar.refresh() } }
    }
}
