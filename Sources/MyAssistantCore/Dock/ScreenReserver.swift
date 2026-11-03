import AppKit
import ApplicationServices

@MainActor
public final class ScreenReserver {
    private var strip: CGRect?
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceToken: NSObjectProtocol?
    private var prompted = false

    public init() {}

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

    public func reserve(_ strip: CGRect?) {
        self.strip = strip
        guard strip != nil else { stop(); return }
        let opts = ["AXTrustedCheckOptionPrompt": !prompted] as CFDictionary
        prompted = true
        guard AXIsProcessTrustedWithOptions(opts) else { return }
        start()
        enforceAll()
    }

    private func start() {
        guard workspaceToken == nil else { return }
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app else { return }
                self.observe(app)
                self.enforce(pid: app.processIdentifier)
            }
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular { observe(app) }
    }

    private func stop() {
        if let t = workspaceToken { NSWorkspace.shared.notificationCenter.removeObserver(t) }
        workspaceToken = nil
        for (_, o) in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .defaultMode)
        }
        observers.removeAll()
    }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != getpid(), observers[pid] == nil else { return }
        var obs: AXObserver?
        let cb: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<ScreenReserver>.fromOpaque(refcon).takeUnretainedValue()
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            MainActor.assumeIsolated { me.enforce(pid: pid) }
        }
        guard AXObserverCreate(pid, cb, &obs) == .success, let obs else { return }
        let appEl = AXUIElementCreateApplication(pid)
        let me = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXWindowMovedNotification, kAXWindowResizedNotification, kAXWindowCreatedNotification] {
            AXObserverAddNotification(obs, appEl, n as CFString, me)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
    }

    private func enforceAll() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            enforce(pid: app.processIdentifier)
        }
    }

    private func enforce(pid: pid_t) {
        guard let strip, pid != getpid(),
              let primaryH = NSScreen.screens.first?.frame.height,
              let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(strip) || $0.frame.intersects(strip) })
        else { return }
        let appEl = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return }
        for win in windows {
            guard string(win, kAXSubroleAttribute) == kAXStandardWindowSubrole,
                  bool(win, "AXFullScreen") != true,
                  let ax = frame(win) else { continue }
            let cocoa = CGRect(x: ax.minX, y: primaryH - ax.maxY, width: ax.width, height: ax.height)
            guard let new = Self.clamp(cocoa, avoiding: strip, in: screen.visibleFrame) else { continue }
            var pos = CGPoint(x: new.minX, y: primaryH - new.maxY)
            var size = new.size
            if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, v) }
            if let v = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
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
