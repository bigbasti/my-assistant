import Testing
import CoreGraphics
@testable import MyAssistantCore

@Suite struct ScreenReserverTests {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func maximizedWindowIsShrunk() {
        let strip = DockGeometry.frame(for: .left, in: visible)
        let r = ScreenReserver.clamp(visible, avoiding: strip, in: visible)
        #expect(r == CGRect(x: 360, y: 0, width: 1080, height: 875))
    }
    @Test func windowOutsideStripUntouched() {
        let strip = DockGeometry.frame(for: .left, in: visible)
        let w = CGRect(x: 400, y: 100, width: 600, height: 400)
        #expect(ScreenReserver.clamp(w, avoiding: strip, in: visible) == nil)
    }
    @Test func windowOnRightDockGetsNarrowedFromRight() {
        let strip = DockGeometry.frame(for: .right, in: visible)
        let r = ScreenReserver.clamp(visible, avoiding: strip, in: visible)
        #expect(r == CGRect(x: 0, y: 0, width: 1080, height: 875))
    }
}

extension ScreenReserverTests {
    @Test func refusingWindowIsNotRetried() {
        let target = CGRect(x: 360, y: 0, width: 1080, height: 875)
        let stuck = CGRect(x: 360, y: 0, width: 1200, height: 875)
        let attempt = ScreenReserver.Attempt(target: target, resulting: stuck)
        #expect(!ScreenReserver.shouldApply(target: target, current: stuck, lastAttempt: attempt))
        #expect(ScreenReserver.shouldApply(target: target, current: CGRect(x: 0, y: 0, width: 1440, height: 875), lastAttempt: attempt))
        #expect(ScreenReserver.shouldApply(target: target, current: stuck, lastAttempt: nil))
    }

    @Test func windowHandlingBySubrole() {
        #expect(ScreenReserver.handling(subrole: "AXStandardWindow", regularApp: true) == .fit)
        #expect(ScreenReserver.handling(subrole: "AXDialog", regularApp: true) == .moveOnly)
        #expect(ScreenReserver.handling(subrole: "AXFloatingWindow", regularApp: true) == .moveOnly)
        #expect(ScreenReserver.handling(subrole: "AXSystemDialog", regularApp: true) == .ignore)
        #expect(ScreenReserver.handling(subrole: nil, regularApp: true) == .ignore)
        #expect(ScreenReserver.handling(subrole: "AXStandardWindow", regularApp: false) == .fit)
        #expect(ScreenReserver.handling(subrole: "AXFloatingWindow", regularApp: false) == .ignore)
    }

    @Test func moveOnlyShiftsDialogBesideLeftDockKeepingSize() {
        let strip = DockGeometry.frame(for: .left, in: visible)
        let dialog = CGRect(x: 100, y: 300, width: 400, height: 200)
        #expect(ScreenReserver.moveAside(dialog, avoiding: strip, in: visible) == CGRect(x: 360, y: 300, width: 400, height: 200))
    }

    @Test func moveOnlyShiftsDialogBesideRightDock() {
        let strip = DockGeometry.frame(for: .right, in: visible)
        let dialog = CGRect(x: 1000, y: 300, width: 400, height: 200)
        #expect(ScreenReserver.moveAside(dialog, avoiding: strip, in: visible) == CGRect(x: 680, y: 300, width: 400, height: 200))
    }

    @Test func moveOnlyLeavesNonOverlappingDialog() {
        let strip = DockGeometry.frame(for: .left, in: visible)
        #expect(ScreenReserver.moveAside(CGRect(x: 500, y: 0, width: 300, height: 200), avoiding: strip, in: visible) == nil)
    }
}

@Suite struct FullscreenRuleTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func windowCoveringWholeScreenCounts() {
        #expect(FullscreenRule.isCovering(screen, screen: screen))
        #expect(FullscreenRule.isCovering(screen.insetBy(dx: -0.5, dy: -0.5), screen: screen))
    }
    @Test func maximizedWindowBelowMenuBarDoesNot() {
        #expect(!FullscreenRule.isCovering(CGRect(x: 0, y: 0, width: 1512, height: 949), screen: screen))
        #expect(!FullscreenRule.isCovering(CGRect(x: 100, y: 0, width: 1412, height: 982), screen: screen))
    }
}
