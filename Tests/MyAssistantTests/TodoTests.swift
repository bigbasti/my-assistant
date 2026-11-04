import Testing
import Foundation
import SwiftUI
@testable import MyAssistantCore

@MainActor @Suite struct TodoTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static var berlin: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; return c }

    func store(_ now: Date? = nil) -> (TodoStore, () -> Date) {
        var clock = now ?? t0
        let s = TodoStore(state: PersistedState(), now: { clock }, calendar: Self.berlin)
        return (s, { clock })
    }

    @Test func newTodoIsUncheckedAndOnTop() {
        let (s, _) = store()
        let a = s.add(title: "First")
        let b = s.add(title: "Second")
        #expect(!s.items.first { $0.id == a }!.done)
        #expect(s.visible.map(\.id) == [b, a])
    }

    @Test func checkingHidesFromVisibleButNotFromAll() {
        let (s, _) = store()
        let a = s.add(title: "A"); let b = s.add(title: "B")
        s.toggleDone(a)
        #expect(s.visible.map(\.id) == [b])
        #expect(s.all.map(\.id) == [b, a])
        s.toggleDone(a)
        #expect(Set(s.visible.map(\.id)) == [a, b])
    }

    @Test func dueItemsSortFirstBySoonest() {
        let (s, _) = store()
        let plain = s.add(title: "plain")
        let later = s.add(title: "later"); s.setDue(later, t0.addingTimeInterval(7200))
        let soon = s.add(title: "soon"); s.setDue(soon, t0.addingTimeInterval(600))
        #expect(s.visible.map(\.id) == [soon, later, plain])
    }

    @Test func dueStates() {
        let now = Self.berlin.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))!
        let at = { (d: Int, h: Int) in Self.berlin.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))! }
        #expect(TodoItem.dueState(nil, now: now, calendar: Self.berlin) == .none)
        #expect(TodoItem.dueState(at(4, 9), now: now, calendar: Self.berlin) == .overdue)
        #expect(TodoItem.dueState(at(4, 18), now: now, calendar: Self.berlin) == .today)
        #expect(TodoItem.dueState(at(5, 9), now: now, calendar: Self.berlin) == .upcoming)
    }

    @Test func rescheduleHidesUntilTimeButStaysInAll() {
        var clock = t0
        let s = TodoStore(state: PersistedState(), now: { clock }, calendar: Self.berlin)
        let a = s.add(title: "A")
        s.reschedule(a, .min30)
        #expect(s.visible.isEmpty)
        #expect(s.all.map(\.id) == [a])
        clock = t0.addingTimeInterval(1801)
        #expect(s.visible.map(\.id) == [a])
    }

    @Test func allListsOpenThenSnoozedThenDone() {
        let (s, _) = store()
        let done = s.add(title: "done"); s.toggleDone(done)
        let snoozed = s.add(title: "snoozed"); s.reschedule(snoozed, .hour1)
        let open = s.add(title: "open")
        #expect(s.all.map(\.id) == [open, snoozed, done])
    }

    @Test func deleteRemoves() {
        let (s, _) = store()
        let a = s.add(title: "A")
        s.delete(a)
        #expect(s.all.isEmpty)
    }

    @Test func createFromNotificationKeepsReference() {
        let (s, _) = store()
        let teams = AssistantNotification(id: "teams:1", kind: .teams, title: "Teams message", sender: "Anna",
                                          preview: "Please review the deck", openURL: URL(string: "msteams:/l/chat/x/0"),
                                          firstSurfacedAt: t0, surfacedAt: t0)
        let mail = AssistantNotification(id: "mail:1", kind: .mail, title: "Quarterly report", sender: "Ben",
                                         preview: "p", openURL: nil, firstSurfacedAt: t0, surfacedAt: t0)
        let a = s.add(from: teams), b = s.add(from: mail)
        let ta = s.items.first { $0.id == a }!, tb = s.items.first { $0.id == b }!
        #expect(ta.title == "Please review the deck")
        #expect(ta.reference == TodoReference(kind: .teams, url: URL(string: "msteams:/l/chat/x/0"), label: "Anna"))
        #expect(tb.title == "Quarterly report")
        #expect(tb.reference == TodoReference(kind: .mail, url: nil, label: "Ben"))
    }

    @Test func createFromEventUsesTitleAndWebLink() {
        let (s, _) = store()
        let e = CalendarEvent(id: "e1", subject: "Sprint review", start: t0, end: t0.addingTimeInterval(1800),
                              webLink: URL(string: "ical://ekevent/x"))
        let id = s.add(from: e)
        let t = s.items.first { $0.id == id }!
        #expect(t.title == "Sprint review")
        #expect(t.reference == TodoReference(kind: .calendar, url: URL(string: "ical://ekevent/x"), label: "Sprint review"))
    }

    @Test func notesWithFormattingSurviveSaving() throws {
        var note = AttributedString("Bold red")
        note[note.range(of: "Bold")!].font = .body.bold()
        note[note.range(of: "red")!].foregroundColor = .red
        var state = PersistedState()
        state.todos = [TodoItem(title: "T", note: note, createdAt: t0)]
        let back = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        let decoded = back.todos[0].note
        #expect(String(decoded.characters) == "Bold red")
        #expect(decoded[decoded.range(of: "Bold")!].font != nil)
        #expect(decoded[decoded.range(of: "red")!].foregroundColor != nil)
    }

    @Test func oldStateHasNoTodos() throws {
        let s = try JSONDecoder().decode(PersistedState.self, from: #"{"settings":{}}"#.data(using: .utf8)!)
        #expect(s.todos.isEmpty)
    }
}

@MainActor @Suite struct TodoReferenceOpenTests {
    func model() -> AppModel {
        AppModel(persistence: Persistence(url: FileManager.default.temporaryDirectory.appendingPathComponent("td-\(UUID()).json")))
    }
    @Test func mailReferenceLaunchesOutlook() {
        let m = model(); var launched: [String] = []
        m.launchApp = { launched.append($0) }
        m.open(TodoReference(kind: .mail, url: nil, label: "Ben"))
        #expect(launched == ["com.microsoft.Outlook"])
    }
    @Test func teamsAndEventReferencesOpenTheirLinks() {
        let m = model(); var opened: [URL?] = []
        m.opener = { opened.append($0) }
        m.open(TodoReference(kind: .teams, url: URL(string: "msteams:/l/chat/x/0?context=1"), label: "A"))
        m.open(TodoReference(kind: .calendar, url: URL(string: "ical://ekevent/x"), label: "M"))
        #expect(opened == [URL(string: "msteams:/l/chat/x/0?context=1"), URL(string: "ical://ekevent/x")])
    }
    @Test func todosAreSaved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("td-\(UUID()).json")
        let m = AppModel(persistence: Persistence(url: url))
        m.todos.add(title: "Persist me")
        m.flush()
        #expect(Persistence(url: url).load().todos.map(\.title) == ["Persist me"])
    }
}

@Suite struct NoteFormattingTests {
    @Test func bulletStartsCoverEverySelectedLine() {
        let text = "alpha\nbeta\ngamma"
        // Selection from inside "alpha" to inside "beta": lines 0 and 6 start.
        #expect(NoteFormatting.lineStarts(in: text, from: 2, to: 8) == [0, 6])
        #expect(NoteFormatting.lineStarts(in: text, from: 12, to: 12) == [11])
        #expect(NoteFormatting.lineStarts(in: "", from: 0, to: 0) == [0])
    }
    @Test func bulletsToggleOff() {
        #expect(NoteFormatting.allBulleted(in: "• a\n• b", starts: [0, 4]))
        #expect(!NoteFormatting.allBulleted(in: "• a\nb", starts: [0, 4]))
    }
}

@Suite struct NoteColorTests {
    @Test func uncoloredRunsGetPrimaryWhileEditingAndLoseItWhenSaved() {
        var note = AttributedString("plain red")
        note[note.range(of: "red")!].foregroundColor = .red
        let editing = NoteFormatting.withDefaultColor(note)
        #expect(editing[editing.range(of: "plain")!].foregroundColor == .primary)
        #expect(editing[editing.range(of: "red")!].foregroundColor == .red)
        let saved = NoteFormatting.withoutDefaultColor(editing)
        #expect(saved[saved.range(of: "plain")!].foregroundColor == nil)
        #expect(saved[saved.range(of: "red")!].foregroundColor == .red)
    }
}
