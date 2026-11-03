import Foundation

public enum SourceStatus: Equatable, Sendable {
    case disabled, ok(Date), noAlertsYet, needsFullDiskAccess, needsCalendarAccess, error(String)
}
