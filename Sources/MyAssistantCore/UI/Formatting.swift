import Foundation

public func countdownLabel(_ remaining: TimeInterval) -> String {
    let s = max(0, Int(remaining.rounded(.up)))
    return String(format: "%02d:%02d", s / 60, s % 60)
}

public func relativeTime(from date: Date, now: Date) -> String {
    let s = Int(now.timeIntervalSince(date))
    if s < 60 { return "now" }
    if s < 3600 { return "\(s / 60) min ago" }
    if s < 86400 { return "\(s / 3600) h ago" }
    return "\(s / 86400) d ago"
}

public func timeRangeLabel(start: Date, end: Date) -> String {
    let f = Date.FormatStyle(date: .omitted, time: .shortened)
    return "\(start.formatted(f)) – \(end.formatted(f))"
}
