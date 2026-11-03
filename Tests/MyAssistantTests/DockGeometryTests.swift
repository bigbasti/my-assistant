import Testing
import CoreGraphics
@testable import MyAssistantCore

@Suite struct DockGeometryTests {
    let s1 = (id: CGDirectDisplayID(1), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
    let s2 = (id: CGDirectDisplayID(2), visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1050))

    @Test func leftFrame() {
        #expect(DockGeometry.frame(for: .left, in: s1.visibleFrame) == CGRect(x: 0, y: 0, width: 360, height: 875))
    }
    @Test func rightFrame() {
        #expect(DockGeometry.frame(for: .right, in: s1.visibleFrame) == CGRect(x: 1080, y: 0, width: 360, height: 875))
    }
    @Test func secondScreenOffset() {
        #expect(DockGeometry.frame(for: .right, in: s2.visibleFrame).origin.x == 3000)
    }
    @Test func dropNearRightEdgeOfScreen2PicksScreen2Right() {
        let p = DockGeometry.nearestPlacement(dropPoint: CGPoint(x: 3300, y: 500), screens: [s1, s2])
        #expect(p == DockPlacement(screenID: 2, edge: .right))
    }
    @Test func dropOnLeftHalfPicksLeft() {
        let p = DockGeometry.nearestPlacement(dropPoint: CGPoint(x: 100, y: 500), screens: [s1, s2])
        #expect(p == DockPlacement(screenID: 1, edge: .left))
    }
    @Test func missingScreenFallsBackToMain() {
        let r = DockGeometry.resolve(DockPlacement(screenID: 9, edge: .right), screens: [s1], mainID: 1)
        #expect(r.id == 1)
        #expect(r.frame == CGRect(x: 1080, y: 0, width: 360, height: 875))
    }
}
