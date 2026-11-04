import Foundation
import EventKit
import Observation

@Observable @MainActor
public final class SettingsController {
    public let model: AppModel
    public private(set) var launchError: String?

    @ObservationIgnored private let restartSources: @MainActor () -> Void
    @ObservationIgnored private let dockTo: @MainActor (DockEdge) -> Void
    @ObservationIgnored private let setReserving: @MainActor (Bool) -> Void
    @ObservationIgnored private let loginItem: LoginItem
    @ObservationIgnored private let openURL: @MainActor (URL) -> Void
    @ObservationIgnored private let calendarAuthorization: () -> EKAuthorizationStatus

    public init(model: AppModel,
                restartSources: @escaping @MainActor () -> Void,
                dockTo: @escaping @MainActor (DockEdge) -> Void,
                setReserving: @escaping @MainActor (Bool) -> Void,
                loginItem: LoginItem = SystemLoginItem(),
                openURL: @escaping @MainActor (URL) -> Void = { Opener.open($0) },
                calendarAuthorization: @escaping () -> EKAuthorizationStatus = { EKEventStore.authorizationStatus(for: .event) }) {
        self.model = model
        self.restartSources = restartSources
        self.dockTo = dockTo
        self.setReserving = setReserving
        self.loginItem = loginItem
        self.openURL = openURL
        self.calendarAuthorization = calendarAuthorization
    }

    private func changed() { model.save() }

    public func setSource(_ kind: SourceKind, enabled: Bool) {
        if enabled { model.settings.enabled.insert(kind) } else { model.settings.enabled.remove(kind) }
        if !enabled { model.state.bootstrappedSources.remove(kind) }
        if !enabled && kind == .calendar { model.events.replace([]) }
        changed()
        restartSources()
    }

    public func openFullDiskAccessSettings() {
        openPrivacy("Privacy_AllFiles")
    }

    public func fixCalendarAccess() async {
        if calendarAuthorization() == .notDetermined {
            restartSources()
        } else {
            openPrivacy("Privacy_Calendars")
        }
    }

    private func openPrivacy(_ pane: String) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { openURL(u) }
    }

    public func setReserveScreenSpace(_ on: Bool) {
        model.settings.reserveScreenSpace = on
        changed()
        setReserving(on)
    }

    public func setDockEdge(_ edge: DockEdge) {
        dockTo(edge)
        changed()
    }

    public func setPlayTone(_ on: Bool) {
        model.settings.playTone = on
        changed()
    }

    public func setBackgroundOpacity(_ value: Double) {
        model.settings.backgroundOpacity = min(1, max(0, value))
        changed()
    }

    public func setHideFromScreenSharing(_ on: Bool) {
        model.settings.hideFromScreenSharing = on
        changed()
    }

    // MARK: watched apps

    /// Re-runs the app keeper right away so changes take effect without waiting for its timer.
    public var onWatchedChange: (@MainActor () -> Void)?
    /// Source of live per-item status for the settings list.
    public var keeper: AppKeeper?

    public func setKeepAppsRunning(_ on: Bool) {
        model.settings.keepAppsRunning = on
        watchedChanged()
    }

    public func addWatched(_ item: WatchedItem) {
        guard !model.settings.watched.contains(where: { $0.target == item.target }) else { return }
        model.settings.watched.append(item)
        watchedChanged()
    }

    public func setWatched(_ id: UUID, enabled: Bool) {
        guard let i = model.settings.watched.firstIndex(where: { $0.id == id }) else { return }
        model.settings.watched[i].enabled = enabled
        watchedChanged()
    }

    public func removeWatched(_ id: UUID) {
        model.settings.watched.removeAll { $0.id == id }
        watchedChanged()
    }

    private func watchedChanged() {
        changed()
        onWatchedChange?()
    }

    public func setLaunchAtLogin(_ on: Bool) {
        launchError = nil
        do {
            try loginItem.set(on)
            model.settings.launchAtLogin = on
        } catch {
            launchError = error.localizedDescription
            model.settings.launchAtLogin = loginItem.isEnabled
        }
        changed()
    }

    public func syncLaunchAtLogin() {
        let on = loginItem.isEnabled
        if model.settings.launchAtLogin != on {
            model.settings.launchAtLogin = on
            changed()
        }
    }
}
