import Foundation

public enum CountdownPhase: Equatable, Sendable {
    case idle
    case countdown(TimeInterval)
    case warning(TimeInterval)
    case pulsing(TimeInterval)
    case started

    /// idle >= 600; countdown (300,600); warning (60,300]; pulsing (0,60]; started <= 0.
    public static func phase(start: Date, now: Date) -> CountdownPhase {
        let r = start.timeIntervalSince(now)
        if r >= 600 { return .idle }
        if r > 300 { return .countdown(r) }
        if r > 60 { return .warning(r) }
        if r > 0 { return .pulsing(r) }
        return .started
    }
}
