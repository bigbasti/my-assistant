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
}
