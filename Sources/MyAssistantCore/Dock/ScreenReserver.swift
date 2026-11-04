import AppKit
import ApplicationServices

@MainActor
public final class ScreenReserver {
    private var strip: CGRect?
    private struct Entry {
        var observer: AXObserver
        var app: AXUIElement
        var windows: [Int: AXUIElement] = [:]
    }
    private var entries: [pid_t: Entry] = [:]
    private var attempts: [Int: Attempt] = [:]
    private var tokens: [NSObjectProtocol] = []
    private var prompted = false
    private var isEnforcing = false
    private var reservedScreen: CGDirectDisplayID?
    private var ledger = RestoreLedger()
    private var handles: [Int: AXUIElement] = [:]

    private func restoreWindows(leaving screenID: CGDirectDisplayID) {
        guard let primaryH = NSScreen.screens.first?.frame.height else { ledger.forget(screenID: screenID); return }
        var current: [Int: CGRect] = [:]
        for key in ledger.keys(on: screenID) {
            if let win = handles[key], let ax = frame(win) {
                current[key] = CGRect(x: ax.minX, y: primaryH - ax.maxY, width: ax.width, height: ax.height)
            }
        }
        for (key, original) in ledger.restorations(leaving: screenID, current: current) {
            guard let win = handles[key] else { continue }
            var size = original.size
            var pos = CGPoint(x: original.minX, y: primaryH - original.maxY)
            if let v = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
            if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, v) }
            attempts[key] = nil
        }
        for key in ledger.keys(on: screenID) { handles[key] = nil }
        ledger.forget(screenID: screenID)
    }

    public struct Attempt: Equatable {
        public var target: CGRect
        public var resulting: CGRect
        public init(target: CGRect, resulting: CGRect) { self.target = target; self.resulting = resulting }
    }

    private let isTrusted: () -> Bool
    private var trustTimer: Timer?
    private var activeToken: NSObjectProtocol?

    public init(isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) { self.isTrusted = isTrusted }

    /// Pure decision: should enforcement start now?
    public nonisolated static func shouldStartEnforcing(trusted: Bool, strip: CGRect?, enforcing: Bool) -> Bool {
        trusted && strip != nil && !enforcing
    }

    var isWatchingTrust: Bool { trustTimer != nil }

    /// Re-checks trust; starts enforcement and stops watching once trusted.
    func recheckTrust() {
        guard strip != nil, isTrusted() else { return }
        stopTrustWatch()
        start()
        enforceAll()
    }

    private func startTrustWatch() {
        guard trustTimer == nil else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheckTrust() }
        }
        activeToken = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheckTrust() }
        }
    }

    private func stopTrustWatch() {
        trustTimer?.invalidate(); trustTimer = nil
        if let t = activeToken { NotificationCenter.default.removeObserver(t); activeToken = nil }
    }

    /// Pure: false when the previous attempt aimed at the same target and the window ended up
    /// exactly where it is now (it refuses to move/resize), so retrying would loop forever.
    public nonisolated static func shouldApply(target: CGRect, current: CGRect, lastAttempt: Attempt?) -> Bool {
        guard let a = lastAttempt else { return true }
        return !(a.target == target && a.resulting == current)
    }

    public enum WindowHandling: Equatable, Sendable { case fit, moveOnly, ignore }

    /// Standard windows are resized to fit beside the panel; dialogs and floating windows of
    /// regular apps (e.g. Outlook reminders) are only moved. Menu-bar apps' extras are left alone.
    public nonisolated static func handling(subrole: String?, regularApp: Bool) -> WindowHandling {
        switch subrole {
        case "AXStandardWindow": .fit
        case "AXDialog", "AXFloatingWindow": regularApp ? .moveOnly : .ignore
        default: .ignore
        }
    }

    /// Pure: shifts the window horizontally out of the strip keeping its size, or nil if no change.
    public nonisolated static func moveAside(_ window: CGRect, avoiding strip: CGRect, in visible: CGRect) -> CGRect? {
        guard window.intersects(strip), strip.width > 0 else { return nil }
        var r = window
        if strip.midX < visible.midX {
            r.origin.x = min(strip.maxX, visible.maxX - window.width)
        } else {
            r.origin.x = max(visible.minX, strip.minX - window.width)
        }
        return r == window ? nil : r
    }

    /// Pure: returns the new frame (Cocoa coords) or nil when no change is needed.
    public nonisolated static func clamp(_ window: CGRect, avoiding strip: CGRect, in visible: CGRect) -> CGRect? {
        guard window.intersects(strip), strip.width > 0 else { return nil }
        let avail: CGRect
        if strip.midX < visible.midX {
            avail = CGRect(x: strip.maxX, y: visible.minY, width: visible.maxX - strip.maxX, height: visible.height)
        } else {
            avail = CGRect(x: visible.minX, y: visible.minY, width: strip.minX - visible.minX, height: visible.height)
        }
        let w = min(window.width, avail.width), h = min(window.height, avail.height)
        let x = min(max(window.minX, avail.minX), avail.maxX - w)
        let y = min(max(window.minY, avail.minY), avail.maxY - h)
        let result = CGRect(x: x, y: y, width: w, height: h)
        return result == window ? nil : result
    }

    public func reserve(_ strip: CGRect?, screenID: CGDirectDisplayID? = nil) {
        // Leaving a screen (or turning reservation off): put back windows we resized there.
        if let previous = reservedScreen, previous != screenID {
            restoreWindows(leaving: previous)
        }
        reservedScreen = strip == nil ? nil : screenID
        self.strip = strip
        guard strip != nil else { stop(); return }
        let opts = ["AXTrustedCheckOptionPrompt": !prompted] as CFDictionary
        prompted = true
        guard AXIsProcessTrustedWithOptions(opts) else { startTrustWatch(); return }
        stopTrustWatch()
        start()
        enforceAll()
    }

    private func start() {
        guard tokens.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter
        tokens.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app else { return }
                self.observe(app)
                self.enforce(pid: app.processIdentifier)
            }
        })
        tokens.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let self, let app { self.remove(pid: app.processIdentifier) }
            }
        })
        tokens.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app else { return }
                self.observe(app)
                self.enforce(pid: app.processIdentifier)
            }
        })
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular { observe(app) }
        startSweep()
    }

    private func stop() {
        stopTrustWatch()
        sweepTimer?.invalidate(); sweepTimer = nil
        releaseTimer?.invalidate(); releaseTimer = nil
        pendingRelease.removeAll()
        let nc = NSWorkspace.shared.notificationCenter
        tokens.forEach { nc.removeObserver($0) }
        tokens.removeAll()
        for pid in Array(entries.keys) { remove(pid: pid) }
        attempts.removeAll()
    }

    private func remove(pid: pid_t) {
        guard let e = entries.removeValue(forKey: pid) else { return }
        AXObserverRemoveNotification(e.observer, e.app, kAXWindowCreatedNotification as CFString)
        for (key, w) in e.windows {
            for n in Self.windowNotifications { AXObserverRemoveNotification(e.observer, w, n as CFString) }
            attempts[key] = nil
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(e.observer), .defaultMode)
    }

    private static let windowNotifications = [
        kAXWindowMovedNotification, kAXWindowResizedNotification, kAXUIElementDestroyedNotification,
    ]

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != getpid() else { return }
        if entries[pid] == nil {
            var obs: AXObserver?
            let cb: AXObserverCallback = { _, element, notification, refcon in
                guard let refcon else { return }
                let me = Unmanaged<ScreenReserver>.fromOpaque(refcon).takeUnretainedValue()
                var pid: pid_t = 0
                AXUIElementGetPid(element, &pid)
                let name = notification as String
                MainActor.assumeIsolated { me.handle(name, element: element, pid: pid) }
            }
            guard AXObserverCreate(pid, cb, &obs) == .success, let obs else { return }
            let appEl = AXUIElementCreateApplication(pid)
            AXObserverAddNotification(obs, appEl, kAXWindowCreatedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
            entries[pid] = Entry(observer: obs, app: appEl)
        }
        registerWindows(pid: pid)
    }

    private func registerWindows(pid: pid_t) {
        guard let e = entries[pid] else { return }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e.app, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return }
        windows.forEach { register(window: $0, pid: pid) }
    }

    private func register(window: AXUIElement, pid: pid_t) {
        guard var e = entries[pid] else { return }
        let key = Int(CFHash(window))
        guard e.windows[key] == nil else { return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.windowNotifications { AXObserverAddNotification(e.observer, window, n as CFString, me) }
        e.windows[key] = window
        entries[pid] = e
    }

    private func handle(_ name: String, element: AXUIElement, pid: pid_t) {
        switch name {
        case kAXWindowCreatedNotification:
            register(window: element, pid: pid)
            enforce(pid: pid)
        case kAXUIElementDestroyedNotification:
            let key = Int(CFHash(element))
            attempts[key] = nil
            if var e = entries[pid], let w = e.windows.removeValue(forKey: key) {
                for n in Self.windowNotifications { AXObserverRemoveNotification(e.observer, w, n as CFString) }
                entries[pid] = e
            }
        default:
            // While the user is still dragging or resizing, wait for the mouse to be released;
            // otherwise the window jumps around under the cursor.
            if NSEvent.pressedMouseButtons & 1 != 0 { enforceAfterRelease(pid: pid) } else { enforce(pid: pid) }
        }
    }

    private var pendingRelease: Set<pid_t> = []
    private var releaseTimer: Timer?

    private func enforceAfterRelease(pid: pid_t) {
        pendingRelease.insert(pid)
        guard releaseTimer == nil else { return }
        releaseTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self.releaseTimer?.invalidate(); self.releaseTimer = nil
                let pids = self.pendingRelease; self.pendingRelease.removeAll()
                pids.forEach { self.enforce(pid: $0) }
            }
        }
    }

    private var sweepTimer: Timer?

    /// Safety net for apps (e.g. Electron-based Teams/Outlook) that don't reliably post AX window events.
    private func startSweep() {
        guard sweepTimer == nil else { return }
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self.enforceAll()
            }
        }
    }

    private func enforceAll() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observe(app)
            enforce(pid: app.processIdentifier)
        }
    }

    private func enforce(pid: pid_t) {
        guard !isEnforcing else { return }
        isEnforcing = true
        defer { isEnforcing = false }
        guard let strip, pid != getpid(),
              let primaryH = NSScreen.screens.first?.frame.height,
              let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(strip) || $0.frame.intersects(strip) })
        else { return }
        let appEl = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return }
        let regular = NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
        for win in windows {
            let mode = Self.handling(subrole: string(win, kAXSubroleAttribute), regularApp: regular)
            guard mode != .ignore,
                  bool(win, "AXFullScreen") != true,
                  bool(win, "AXMinimized") != true,
                  let ax = frame(win) else { continue }
            let cocoa = CGRect(x: ax.minX, y: primaryH - ax.maxY, width: ax.width, height: ax.height)
            let target = mode == .fit
                ? Self.clamp(cocoa, avoiding: strip, in: screen.visibleFrame)
                : Self.moveAside(cocoa, avoiding: strip, in: screen.visibleFrame)
            guard let new = target else { continue }
            let key = Int(CFHash(win))
            guard Self.shouldApply(target: new, current: cocoa, lastAttempt: attempts[key]) else { continue }
            var pos = CGPoint(x: new.minX, y: primaryH - new.maxY)
            var size = new.size
            if mode == .fit, let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, v) }
            if let v = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
            let after = frame(win).map { CGRect(x: $0.minX, y: primaryH - $0.maxY, width: $0.width, height: $0.height) } ?? cocoa
            attempts[key] = Attempt(target: new, resulting: after)
            if let screenID = reservedScreen {
                ledger.record(key: key, screenID: screenID, original: cocoa, applied: after)
                handles[key] = win
            }
        }
    }

    private func string(_ el: AXUIElement, _ attr: String) -> String? {
        var r: CFTypeRef?
        AXUIElementCopyAttributeValue(el, attr as CFString, &r)
        return r as? String
    }
    private func bool(_ el: AXUIElement, _ attr: String) -> Bool? {
        var r: CFTypeRef?
        AXUIElementCopyAttributeValue(el, attr as CFString, &r)
        return r as? Bool
    }
    private func frame(_ el: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        var pt = CGPoint.zero, sz = CGSize.zero
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s) == .success,
              let p, let s,
              AXValueGetValue(p as! AXValue, .cgPoint, &pt),
              AXValueGetValue(s as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: pt, size: sz)
    }
}
