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

@Suite struct DueDateMathTests {
    static var berlin: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Berlin")!; c.firstWeekday = 2; return c
    }
    let cal = Self.berlin
    func d(_ day: Int, _ month: Int = 11, _ h: Int = 0, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: h, minute: m))!
    }

    @Test func monthGridStartsOnFirstWeekdayAndHasWholeWeeks() {
        let grid = DueDateMath.monthGrid(containing: d(4), calendar: cal)
        #expect(grid.count % 7 == 0)
        // 1 Nov 2026 is a Sunday; with Monday first, the grid starts on Mon 26 Oct.
        #expect(grid.first == d(26, 10))
        #expect(grid.contains(d(30)) && grid.contains(d(1)))
    }

    @Test func presets() {
        let now = d(4, 11, 10, 30) // Wednesday 10:30
        let p = DueDateMath.presets(now: now, calendar: cal)
        #expect(p.map(\.label) == ["Today 17:00", "Tomorrow 9:00", "Next Monday 9:00", "In a week"])
        #expect(p[0].date == d(4, 11, 17))
        #expect(p[1].date == d(5, 11, 9))
        #expect(p[2].date == d(9, 11, 9))
        #expect(p[3].date == d(11, 11, 10, 30))
    }

    @Test func todayPresetSkippedAfterFive() {
        let p = DueDateMath.presets(now: d(4, 11, 18), calendar: cal)
        #expect(p.first?.label == "Tomorrow 9:00")
    }

    @Test func combineKeepsDayAndSetsTime() {
        #expect(DueDateMath.setting(hour: 15, minute: 0, on: d(9, 11, 9, 45), calendar: cal) == d(9, 11, 15))
        #expect(DueDateMath.setting(day: d(12), keepingTimeOf: d(9, 11, 15, 30), calendar: cal) == d(12, 11, 15, 30))
    }
}
