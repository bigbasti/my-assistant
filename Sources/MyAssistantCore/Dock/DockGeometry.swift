import CoreGraphics

public enum DockEdge: String, Codable, Sendable { case left, right }

public struct DockPlacement: Codable, Equatable, Sendable {
    public var screenID: CGDirectDisplayID
    public var edge: DockEdge
    /// Stable display UUID; display numbers can change when a monitor is reconnected.
    public var screenUUID: String?
    public init(screenID: CGDirectDisplayID, edge: DockEdge, screenUUID: String? = nil) {
        self.screenID = screenID
        self.edge = edge
        self.screenUUID = screenUUID
    }
}

/// Remembers the frames of windows the reserver changed on a screen, so they can be put back
/// when the panel leaves that screen. Only the frame from before the first change is kept.
public struct RestoreLedger: Sendable {
    struct Entry: Sendable { var screenID: CGDirectDisplayID; var original: CGRect; var applied: CGRect }
    private var entries: [Int: Entry] = [:]

    public init() {}

    public mutating func record(key: Int, screenID: CGDirectDisplayID, original: CGRect, applied: CGRect) {
        if var e = entries[key], e.screenID == screenID {
            e.applied = applied
            entries[key] = e
        } else {
            entries[key] = Entry(screenID: screenID, original: original, applied: applied)
        }
    }

    /// Original frames for windows on `screenID` that are still exactly where the reserver put them.
    public func restorations(leaving screenID: CGDirectDisplayID, current: [Int: CGRect]) -> [Int: CGRect] {
        var out: [Int: CGRect] = [:]
        for (key, e) in entries where e.screenID == screenID {
            if let now = current[key], now == e.applied { out[key] = e.original }
        }
        return out
    }

    public mutating func forget(screenID: CGDirectDisplayID) {
        entries = entries.filter { $0.value.screenID != screenID }
    }

    public func keys(on screenID: CGDirectDisplayID) -> [Int] {
        entries.filter { $0.value.screenID == screenID }.map(\.key)
    }
}

public enum DockGeometry {
    public static let width: CGFloat = 360

    public static func frame(for edge: DockEdge, in visibleFrame: CGRect) -> CGRect {
        let x = edge == .left ? visibleFrame.minX : visibleFrame.maxX - width
        return CGRect(x: x, y: visibleFrame.minY, width: width, height: visibleFrame.height)
    }

    public static func nearestPlacement(
        dropPoint: CGPoint,
        screens: [(id: CGDirectDisplayID, visibleFrame: CGRect)]
    ) -> DockPlacement {
        let screen = screens.first { $0.visibleFrame.contains(dropPoint) }
            ?? screens.min { dist($0.visibleFrame, dropPoint) < dist($1.visibleFrame, dropPoint) }
        guard let screen else { return DockPlacement(screenID: 0, edge: .right) }
        return DockPlacement(screenID: screen.id, edge: dropPoint.x < screen.visibleFrame.midX ? .left : .right)
    }

    public static func resolve(
        _ p: DockPlacement,
        screens: [(id: CGDirectDisplayID, visibleFrame: CGRect)],
        mainID: CGDirectDisplayID
    ) -> (id: CGDirectDisplayID, frame: CGRect) {
        let screen = screens.first { $0.id == p.screenID }
            ?? screens.first { $0.id == mainID }
            ?? screens.first
        guard let screen else { return (mainID, .zero) }
        return (screen.id, frame(for: p.edge, in: screen.visibleFrame))
    }

    /// Points the placement at the screen with its saved UUID, if that screen is connected.
    public static func rebind(_ p: DockPlacement, uuids: [CGDirectDisplayID: String]) -> DockPlacement {
        guard let uuid = p.screenUUID, let id = uuids.first(where: { $0.value == uuid })?.key else { return p }
        return DockPlacement(screenID: id, edge: p.edge, screenUUID: uuid)
    }

    private static func dist(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        hypot(r.midX - p.x, r.midY - p.y)
    }
}
