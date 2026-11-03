import Foundation

public enum SnoozeOption: Equatable, Hashable, Sendable {
    case min10, min30, hour1, hour3, tomorrow
    case custom(Date)

    public static let presets: [SnoozeOption] = [.min10, .min30, .hour1, .hour3, .tomorrow]

    public var label: String {
        switch self {
        case .min10: "in 10 Min"
        case .min30: "in 30 Min"
        case .hour1: "in 1 Hour"
        case .hour3: "in 3 Hours"
        case .tomorrow: "Tomorrow"
        case .custom: "Custom…"
        }
    }

    public func resurfaceDate(now: Date, firstSurfacedAt: Date, calendar: Calendar) -> Date {
        switch self {
        case .min10: return now.addingTimeInterval(10 * 60)
        case .min30: return now.addingTimeInterval(30 * 60)
        case .hour1: return now.addingTimeInterval(3600)
        case .hour3: return now.addingTimeInterval(3 * 3600)
        case .custom(let date): return date
        case .tomorrow:
            let tod = calendar.dateComponents([.hour, .minute, .second], from: firstSurfacedAt)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            return calendar.date(bySettingHour: tod.hour!, minute: tod.minute!, second: tod.second!, of: nextDay)!
        }
    }
}
