import AppKit

/// Applies the "hide from screen sharing" setting to every window of the app except Settings.
/// Popovers (snooze, delete confirmation) are separate windows created on demand, so the rule is
/// re-applied whenever AppKit updates the app's windows.
@MainActor
public final class ScreenSharingGuard {
    private let model: AppModel
    private var token: NSObjectProtocol?

    public init(model: AppModel) { self.model = model }

    public nonisolated static func sharingType(hide: Bool, isSettingsWindow: Bool) -> NSWindow.SharingType {
        hide && !isSettingsWindow ? .none : .readOnly
    }

    public func start() {
        apply()
        token = NotificationCenter.default.addObserver(forName: NSApplication.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
    }

    public func stop() {
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
    }

    private func apply() {
        let hide = model.settings.hideFromScreenSharing
        for window in NSApp.windows {
            let isSettings = window.identifier?.rawValue.contains("Settings") == true
            let wanted = Self.sharingType(hide: hide, isSettingsWindow: isSettings)
            if window.sharingType != wanted { window.sharingType = wanted }
        }
    }
}
