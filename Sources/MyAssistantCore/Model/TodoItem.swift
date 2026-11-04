import Foundation
import SwiftUI

/// Where a to-do came from, so it can be opened like the original card.
public struct TodoReference: Codable, Equatable, Sendable {
    public var kind: SourceKind
    public var url: URL?
    /// Sender or meeting title, shown as a hint on the to-do.
    public var label: String
    public init(kind: SourceKind, url: URL?, label: String) { self.kind = kind; self.url = url; self.label = label }
}

public struct TodoItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    /// Rich-text note (bold, underline, colour, size, links), edited visually.
    public var note: AttributedString
    public var done: Bool
    public var createdAt: Date
    public var due: Date?
    public var snoozedUntil: Date?
    public var reference: TodoReference?

    public init(id: UUID = UUID(), title: String, note: AttributedString = AttributedString(), done: Bool = false,
                createdAt: Date, due: Date? = nil, snoozedUntil: Date? = nil, reference: TodoReference? = nil) {
        self.id = id; self.title = title; self.note = note; self.done = done
        self.createdAt = createdAt; self.due = due; self.snoozedUntil = snoozedUntil; self.reference = reference
    }

    public enum DueState: Equatable, Sendable { case none, upcoming, today, overdue }

    public static func dueState(_ due: Date?, now: Date, calendar: Calendar) -> DueState {
        guard let due else { return .none }
        if due < now { return .overdue }
        return calendar.isDate(due, inSameDayAs: now) ? .today : .upcoming
    }

    private enum CodingKeys: String, CodingKey { case id, title, note, done, createdAt, due, snoozedUntil, reference }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        // Notes are stored with the SwiftUI attribute scope so fonts, colours and underline survive.
        note = (try? c.decode(AttributedString.self, forKey: .note, configuration: AttributeScopes.SwiftUIAttributes.self))
            ?? AttributedString()
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        reference = try c.decodeIfPresent(TodoReference.self, forKey: .reference)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(note, forKey: .note, configuration: AttributeScopes.SwiftUIAttributes.self)
        try c.encode(done, forKey: .done)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(due, forKey: .due)
        try c.encodeIfPresent(snoozedUntil, forKey: .snoozedUntil)
        try c.encodeIfPresent(reference, forKey: .reference)
    }
}
