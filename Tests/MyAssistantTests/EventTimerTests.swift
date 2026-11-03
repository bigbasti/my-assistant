import Testing
import Foundation
@testable import MyAssistantCore

@Suite struct EventTimerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func phase(_ remaining: TimeInterval) -> CountdownPhase {
        CountdownPhase.phase(start: now.addingTimeInterval(remaining), now: now)
    }
    @Test func boundaries() {
        #expect(phase(600) == .idle)
        #expect(phase(599) == .countdown(599))
        #expect(phase(301) == .countdown(301))
        #expect(phase(300) == .warning(300))
        #expect(phase(61) == .warning(61))
        #expect(phase(60) == .pulsing(60))
        #expect(phase(59) == .pulsing(59))
        #expect(phase(1) == .pulsing(1))
        #expect(phase(0) == .started)
        #expect(phase(-30) == .started)
    }
}
