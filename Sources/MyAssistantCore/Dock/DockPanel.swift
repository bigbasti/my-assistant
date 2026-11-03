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
    }
}

@MainActor
public final class DockController {
    public private(set) var placement: DockPlacement
    public var onPlacementChange: ((DockPlacement) -> Void)?
    public var reserver: ScreenReserver?

    private let panel: DockPanel
    private let previewWindow: NSWindow
    private var dragTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    public init<Content: View>(content: Content, placement: DockPlacement? = nil) {
        self.placement = placement ?? DockPlacement(
            screenID: Self.mainScreenID, edge: .left)
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

        let host = NSHostingView(rootView: content.environment(\.dockBeginDrag, { [weak self] in self?.beginDrag() }))
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
        placement = p
        applyFrame(animated: animated)
        onPlacementChange?(p)
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
                self.previewWindow.setFrame(DockGeometry.frame(for: n.edge, in: self.visible(of: n.screenID)), display: true)
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard let self else { return }
            self.dragTask = nil
            self.previewWindow.orderOut(nil)
            guard !Task.isCancelled else { return }
            self.dock(to: self.nearest(NSEvent.mouseLocation), animated: true)
        }
    }

    public func cancelDrag() {
        dragTask?.cancel()
    }

    private func nearest(_ point: CGPoint) -> DockPlacement {
        DockGeometry.nearestPlacement(dropPoint: point, screens: Self.screens)
    }

    private func visible(of id: CGDirectDisplayID) -> CGRect {
        Self.screens.first { $0.id == id }?.visibleFrame ?? .zero
    }

    private func reposition() {
        let r = DockGeometry.resolve(placement, screens: Self.screens, mainID: Self.mainScreenID)
        if r.id != placement.screenID {
            placement = DockPlacement(screenID: r.id, edge: placement.edge)
            onPlacementChange?(placement)
        }
        applyFrame(animated: false)
    }

    private func applyFrame(animated: Bool) {
        let r = DockGeometry.resolve(placement, screens: Self.screens, mainID: Self.mainScreenID)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                panel.animator().setFrame(r.frame, display: true)
            }
        } else {
            panel.setFrame(r.frame, display: true)
        }
        reserver?.reserve(r.frame)
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
public extension EnvironmentValues {
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
