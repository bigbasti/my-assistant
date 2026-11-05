import Foundation

/// Fictional example content for README screenshots (`My Assistant --demo`).
/// Never reads real notifications, mail or calendars.
@MainActor
public enum DemoData {
    public static var isEnabled: Bool { CommandLine.arguments.contains("--demo") }

    /// A throwaway state file so demo runs never touch the real one.
    public static var stateURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MyAssistant-demo-\(UUID().uuidString).json")
    }

    public static func populate(_ m: AppModel) {
        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        func note(_ id: String, _ kind: SourceKind, _ sender: String, _ title: String, _ preview: String, _ minutes: Double) -> AssistantNotification {
            AssistantNotification(id: "demo:\(id)", kind: kind, title: title, sender: sender, preview: preview,
                                  openURL: nil, firstSurfacedAt: ago(minutes), surfacedAt: ago(minutes))
        }
        m.notifications.ingest([
            note("1", .teams, "Jane Doe", "Teams message", "Can you review the slides before the 2 pm sync? 🙏", 2),
            note("2", .mail, "Alex Rivera", "Q4 roadmap draft",
                 "Hi! Attached is the first draft of the Q4 roadmap. Comments welcome until Friday.", 7),
            note("3", .teams, "Max Mustermann", "Teams message", "Pushed the fix — pipeline is green ✅", 14),
            note("4", .mail, "Priya Patel", "Team offsite agenda",
                 "Here's the agenda for next week's offsite. Please pick a workshop slot.", 41),
            note("5", .mail, "GitHub", "[my-assistant] New release published", "My Assistant 1.0.3 is available.", 95),
        ])

        let overdue = m.todos.add(title: "Send slides to Jane")
        m.todos.setDue(overdue, ago(30))
        let today = m.todos.add(title: "Review Q4 roadmap")
        m.todos.setDue(today, Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(7200))
        m.todos.add(title: "Book train to Berlin")
        let done = m.todos.add(title: "Submit expense report")
        m.todos.toggleDone(done)

        let join = URL(string: "https://teams.microsoft.com/l/meetup-join/demo")
        func event(_ id: String, _ subject: String, start: Date, minutes: Double, location: String, organizer: String,
                   joinURL: URL? = join) -> CalendarEvent {
            CalendarEvent(id: "demo:\(id)", subject: subject, start: start, end: start.addingTimeInterval(minutes * 60),
                          location: location, organizer: organizer, webLink: nil, joinURL: joinURL)
        }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        m.events.replace([
            event("1", "Daily stand-up", start: ago(3), minutes: 15, location: "Microsoft Teams Meeting", organizer: "Jane Doe"),
            event("2", "Design review", start: now.addingTimeInterval(7 * 60), minutes: 45,
                  location: "Room Atlas", organizer: "Priya Patel"),
            event("3", "1:1 with Alex", start: now.addingTimeInterval(3 * 3600), minutes: 30,
                  location: "Microsoft Teams Meeting", organizer: "Alex Rivera"),
            event("4", "Sprint planning",
                  start: Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: tomorrow)!, minutes: 60,
                  location: "Microsoft Teams Meeting", organizer: "Max Mustermann"),
        ])

        for kind in SourceKind.allCases { m.status[kind] = .ok(now) }
        m.settings.hideFromScreenSharing = false
        m.settings.watched = [
            WatchedItem(name: "Notes", target: .app(bundleID: "com.apple.Notes", path: "/System/Applications/Notes.app")),
            WatchedItem(name: "node server.js", target: .process(path: "/usr/local/bin/node", arguments: ["server.js"])),
        ]
    }
}
