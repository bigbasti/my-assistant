import Foundation
import SwiftUI

public enum SourceKind: String, Codable, CaseIterable, Sendable {
    case teams, mail, calendar

    public var color: Color {
        switch self {
        case .teams: Color(red: 0x62 / 255, green: 0x64 / 255, blue: 0xA7 / 255)
        case .mail: Color(red: 0x00 / 255, green: 0x78 / 255, blue: 0xD4 / 255)
        case .calendar: Color(red: 0x0F / 255, green: 0x9D / 255, blue: 0x58 / 255)
        }
    }

    public var icon: String {
        switch self {
        case .teams: "message.fill"
        case .mail: "envelope.fill"
        case .calendar: "calendar"
        }
    }
}

public struct AssistantNotification: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let kind: SourceKind
    public var title: String
    public var sender: String
    public var preview: String
    public var openURL: URL?
    public var firstSurfacedAt: Date
    public var surfacedAt: Date
    public var snoozedUntil: Date?

    public init(id: String, kind: SourceKind, title: String, sender: String, preview: String,
                openURL: URL? = nil, firstSurfacedAt: Date, surfacedAt: Date, snoozedUntil: Date? = nil) {
        self.id = id; self.kind = kind; self.title = title; self.sender = sender
        self.preview = preview; self.openURL = openURL
        self.firstSurfacedAt = firstSurfacedAt; self.surfacedAt = surfacedAt
        self.snoozedUntil = snoozedUntil
    }
}
