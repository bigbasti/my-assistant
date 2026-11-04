import AppKit

/// "Fake" full screen: a window that covers a whole screen including the menu bar
/// (video players, browsers in presentation mode) without using its own Space.
public enum FullscreenRule {
    public static func isCovering(_ window: CGRect, screen: CGRect) -> Bool {
        window.insetBy(dx: 1, dy: 1).contains(screen.insetBy(dx: 1, dy: 1))
            || (abs(window.minX - screen.minX) <= 1 && abs(window.minY - screen.minY) <= 1
                && abs(window.width - screen.width) <= 1 && abs(window.height - screen.height) <= 1)
    }
}

/// Hides the panel while another app shows something full screen on the panel's screen,
/// and brings it back afterwards. Real full-screen Spaces are excluded via collection behaviour.
@MainActor
public final class FullscreenWatcher {
    private var timer: Timer?
    private let panelScreen: () -> NSScreen?
    private let setHidden: (Bool) -> Void
    private var hidden = false

    public init(panelScreen: @escaping () -> NSScreen?, setHidden: @escaping (Bool) -> Void) {
        self.panelScreen = panelScreen
        self.setHidden = setHidden
    }

    public func start() {
        stop()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.check() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        check()
    }

    public func stop() { timer?.invalidate(); timer = nil }

    func check() {
        let cover = panelScreen().map(Self.isCoveredByOtherApp) ?? false
        if cover != hidden {
            hidden = cover
            setHidden(cover)
        }
    }

    /// True when the frontmost normal-level window on `screen` belongs to another app and covers it fully.
    static func isCoveredByOtherApp(_ screen: NSScreen) -> Bool {
        guard let primaryH = NSScreen.screens.first?.frame.height,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let f = screen.frame
        // CGWindowList uses top-left global coordinates.
        let screenCG = CGRect(x: f.minX, y: primaryH - f.maxY, width: f.width, height: f.height)
        let me = getpid()
        var topOwner: pid_t?
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.5,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let wd = b["Width"], let h = b["Height"] else { continue }
            let rect = CGRect(x: x, y: y, width: wd, height: h)
            guard rect.intersects(screenCG) else { continue }
            // Only the app in front decides. Full-screen players often put a toolbar/overlay
            // window above the video window, so check all of that app's windows at the top.
            if topOwner == nil { topOwner = pid }
            guard pid == topOwner else { return false }
            if FullscreenRule.isCovering(rect, screen: screenCG) { return true }
        }
        return false
    }
}
