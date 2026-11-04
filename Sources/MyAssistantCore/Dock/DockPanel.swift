import AppKit
import SwiftUI

public final class DockPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        // The glass draws its own edge; a window shadow turns into a thick dark border when the panel is key.
        hasShadow = false
        // Transparent pixels would otherwise pass clicks through to the window behind, which
        // makes the invisible resize handles at the panel's sides unclickable.
        ignoresMouseEvents = false
    }
}

@MainActor
public final class DockController {
    public private(set) var placement: DockPlacement
    public var onPlacementChange: ((DockPlacement) -> Void)?
    /// Called once when a side-drag resize ends, with the final width.
    public var onWidthChange: ((CGFloat) -> Void)?
    public private(set) var width: CGFloat
    public var reserver: ScreenReserver?

    private let panel: DockPanel
    private let previewWindow: NSWindow
    private var dragTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    public init<Content: View>(content: Content, placement: DockPlacement? = nil, width: CGFloat = DockGeometry.width) {
        self.width = DockGeometry.clampWidth(width)
        self.placement = DockGeometry.rebind(placement ?? DockPlacement(
            screenID: Self.mainScreenID, edge: .left), uuids: Self.uuids)
        panel = DockPanel(contentRect: NSRect(x: 0, y: 0, width: DockGeometry.width, height: 600))
        previewWindow = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        previewWindow.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        previewWindow.isOpaque = false
        previewWindow.backgroundColor = .clear
        previewWindow.ignoresMouseEvents = true
        previewWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        v.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        v.layer?.borderWidth = 2
        v.layer?.cornerRadius = 12
        previewWindow.contentView = v

        let host = NSHostingView(rootView: content
            .environment(\.dockBeginDrag, { [weak self] in self?.beginDrag() })
            .environment(\.dockBeginResize, { [weak self] in self?.beginResize() }))
        panel.contentView = host

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    public func show() {
        applyFrame(animated: false)
        panel.orderFrontRegardless()
    }

    public func dock(to p: DockPlacement, animated: Bool) {
        // User choice: this becomes the remembered (preferred) placement.
        placement = DockPlacement(screenID: p.screenID, edge: p.edge, screenUUID: Self.uuid(of: p.screenID))
        applyFrame(animated: animated)
        onPlacementChange?(placement)
    }

    /// Called by the drag grip on mouse-down; follows the mouse until mouse-up.
    public func beginDrag() {
        guard dragTask == nil else { return }
        let grab = NSEvent.mouseLocation
        let startOrigin = panel.frame.origin
        previewWindow.orderFront(nil)
        dragTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, NSEvent.pressedMouseButtons & 1 != 0 {
                let m = NSEvent.mouseLocation
                let n = self.nearest(m)
                self.panel.setFrameOrigin(NSPoint(x: startOrigin.x + m.x - grab.x, y: startOrigin.y + m.y - grab.y))
                self.previewWindow.setFrame(DockGeometry.frame(for: n.edge, in: self.visible(of: n.screenID), width: self.width), display: true)
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard let self else { return }
            self.dragTask = nil
            self.previewWindow.orderOut(nil)
            guard !Task.isCancelled else { return }
            self.dock(to: self.nearest(NSEvent.mouseLocation), animated: true)
        }
    }

    private var resizeTask: Task<Void, Never>?

    /// Called by a side handle on mouse-down; resizes live until mouse-up, then reports the width once.
    public func beginResize() {
        guard resizeTask == nil, dragTask == nil else { return }
        let grabX = NSEvent.mouseLocation.x
        let startWidth = width
        resizeTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, NSEvent.pressedMouseButtons & 1 != 0 {
                let w = DockGeometry.resizedWidth(start: startWidth, dragDX: NSEvent.mouseLocation.x - grabX,
                                                  edge: self.currentEdge)
                if w != self.width {
                    self.width = w
                    self.applyFrame(animated: false, reserve: false)
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard let self else { return }
            self.resizeTask = nil
            // Use the final mouse position (the loop may exit before seeing the last movement).
            self.width = DockGeometry.resizedWidth(start: startWidth, dragDX: NSEvent.mouseLocation.x - grabX,
                                                   edge: self.currentEdge).rounded()
            // Push other windows aside only once, at the final width, to avoid fighting them mid-drag.
            self.applyFrame(animated: false)
            self.onWidthChange?(self.width)
        }
    }

    /// Edge the panel is shown on right now (the preferred one, or the fallback screen's same edge).
    private var currentEdge: DockEdge { placement.edge }

    public func cancelDrag() {
        dragTask?.cancel()
    }

    private func nearest(_ point: CGPoint) -> DockPlacement {
        DockGeometry.nearestPlacement(dropPoint: point, screens: Self.screens)
    }

    private func visible(of id: CGDirectDisplayID) -> CGRect {
        Self.screens.first { $0.id == id }?.visibleFrame ?? .zero
    }

    /// Screens came or went. The preferred placement is never overwritten here: if its screen is
    /// missing the panel shows on a fallback screen and returns once the preferred screen is back.
    private func reposition() {
        let rebound = DockGeometry.rebind(placement, uuids: Self.uuids)
        if rebound != placement {
            placement = rebound
            onPlacementChange?(placement)
        }
        applyFrame(animated: false)
    }

    private func applyFrame(animated: Bool, reserve: Bool = true) {
        let r = DockGeometry.resolve(placement, screens: Self.screens, mainID: Self.mainScreenID, width: width)
        // Placements saved before UUIDs were stored get one as soon as their screen is shown.
        if r.id == placement.screenID, placement.screenUUID == nil, let uuid = Self.uuid(of: r.id) {
            placement.screenUUID = uuid
            onPlacementChange?(placement)
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                panel.animator().setFrame(r.frame, display: true)
            }
        } else {
            panel.setFrame(r.frame, display: true)
        }
        if reserve { reserver?.reserve(r.frame, screenID: r.id) }
    }

    static var uuids: [CGDirectDisplayID: String] {
        Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { s in uuid(of: s.displayID).map { (s.displayID, $0) } })
    }

    static func uuid(of id: CGDirectDisplayID) -> String? {
        guard let cf = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, cf) as String?
    }

    static var screens: [(id: CGDirectDisplayID, visibleFrame: CGRect)] {
        NSScreen.screens.map { ($0.displayID, $0.visibleFrame) }
    }
    static var mainScreenID: CGDirectDisplayID { NSScreen.screens.first?.displayID ?? 0 }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

private struct DockBeginDragKey: EnvironmentKey { static let defaultValue: @MainActor () -> Void = {} }
private struct DockBeginResizeKey: EnvironmentKey { static let defaultValue: @MainActor () -> Void = {} }
public extension EnvironmentValues {
    var dockBeginResize: @MainActor () -> Void {
        get { self[DockBeginResizeKey.self] }
        set { self[DockBeginResizeKey.self] = newValue }
    }
    var dockBeginDrag: @MainActor () -> Void {
        get { self[DockBeginDragKey.self] }
        set { self[DockBeginDragKey.self] = newValue }
    }
}

public struct DragGrip: View {
    @Environment(\.dockBeginDrag) private var begin
    public init() {}
    public var body: some View {
        Capsule().fill(.secondary.opacity(0.5)).frame(width: 36, height: 4)
            .frame(maxWidth: .infinity).frame(height: 24)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in begin() })
    }
}

/// Invisible strip on a side of the panel; dragging it changes the panel width.
public struct ResizeHandle: View {
    @Environment(\.dockBeginResize) private var begin
    public init() {}
    public var body: some View {
        Color.clear
            .frame(width: 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in begin() })
    }
}

public struct DockPlaceholderView: View {
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            DragGrip()
            Spacer()
            Text("My Assistant").foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}
