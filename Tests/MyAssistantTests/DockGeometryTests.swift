import Testing
import CoreGraphics
import Foundation
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
    @Test func rebindFollowsUUIDWhenDisplayNumberChanged() {
        let p = DockPlacement(screenID: 7, edge: .left, screenUUID: "UUID-B")
        let r = DockGeometry.rebind(p, uuids: [1: "UUID-A", 2: "UUID-B"])
        #expect(r == DockPlacement(screenID: 2, edge: .left, screenUUID: "UUID-B"))
    }
    @Test func rebindKeepsPlacementWhenUUIDAbsent() {
        let p = DockPlacement(screenID: 7, edge: .right, screenUUID: "UUID-C")
        #expect(DockGeometry.rebind(p, uuids: [1: "UUID-A"]) == p)
        let legacy = DockPlacement(screenID: 2, edge: .right)
        #expect(DockGeometry.rebind(legacy, uuids: [2: "UUID-B"]) == legacy)
    }
    @Test func legacyPlacementDecodesWithoutUUID() throws {
        let p = try JSONDecoder().decode(DockPlacement.self, from: #"{"screenID":2,"edge":"left"}"#.data(using: .utf8)!)
        #expect(p == DockPlacement(screenID: 2, edge: .left))
    }
}

@Suite struct RestoreLedgerTests {
    let original = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let applied = CGRect(x: 360, y: 0, width: 1080, height: 875)

    @Test func keepsFirstOriginalAcrossRepeatedApplies() {
        var l = RestoreLedger()
        l.record(key: 1, screenID: 2, original: original, applied: applied)
        l.record(key: 1, screenID: 2, original: applied, applied: CGRect(x: 360, y: 0, width: 1000, height: 875))
        #expect(l.restorations(leaving: 2, current: [1: CGRect(x: 360, y: 0, width: 1000, height: 875)]) == [1: original])
    }

    @Test func userMovedWindowIsNotRestored() {
        var l = RestoreLedger()
        l.record(key: 1, screenID: 2, original: original, applied: applied)
        #expect(l.restorations(leaving: 2, current: [1: CGRect(x: 500, y: 100, width: 800, height: 600)]).isEmpty)
    }

    @Test func otherScreensAreUntouchedAndLeavingClearsEntries() {
        var l = RestoreLedger()
        l.record(key: 1, screenID: 2, original: original, applied: applied)
        l.record(key: 2, screenID: 3, original: original, applied: applied)
        #expect(l.restorations(leaving: 2, current: [1: applied, 2: applied]) == [1: original])
        l.forget(screenID: 2)
        #expect(l.restorations(leaving: 2, current: [1: applied]).isEmpty)
        #expect(l.restorations(leaving: 3, current: [2: applied]) == [2: original])
    }

    @Test func closedWindowIsSkipped() {
        var l = RestoreLedger()
        l.record(key: 1, screenID: 2, original: original, applied: applied)
        #expect(l.restorations(leaving: 2, current: [:]).isEmpty)
    }
}
