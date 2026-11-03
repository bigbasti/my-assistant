import CoreGraphics

public enum DockEdge: String, Codable, Sendable { case left, right }

public struct DockPlacement: Codable, Equatable, Sendable {
    public var screenID: CGDirectDisplayID
    public var edge: DockEdge
    public init(screenID: CGDirectDisplayID, edge: DockEdge) {
        self.screenID = screenID
        self.edge = edge
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

    private static func dist(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        hypot(r.midX - p.x, r.midY - p.y)
    }
}
