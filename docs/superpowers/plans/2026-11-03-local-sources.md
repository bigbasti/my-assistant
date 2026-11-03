# Local Sources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Microsoft Graph data sources with local macOS sources:
- Teams and Outlook alerts from the macOS notification database;
- today's events from EventKit (Exchange account).

Sign-in is removed.

**Architecture:** Two independent parts feed the existing stores, both pure parsing and mapping with a thin I/O layer.
- A read-only SQLite reader (`NotificationDatabase`) plus a pure mapper (`AlertMapper`) turn notification records into `AssistantNotification`s. A `NotificationWatcher` triggers reads on file changes and on a timer.
- `CalendarReader` turns `EKEvent`s into `EventSnapshot`s and maps those purely to `CalendarEvent`s.
- A `SourceCoordinator` replaces `Poller` and owns both parts. The Graph code is deleted.

**Tech Stack:**
- Swift 6.3 and SwiftUI/AppKit (macOS 26+);
- the system `SQLite3` module and EventKit;
- Swift Testing, run with `swift run MyAssistantTests [--filter X]`. `swift test` runs nothing with Command Line Tools.

**Spec:** `docs/superpowers/specs/2026-11-03-local-sources-design.md`

## Global Constraints

- **Database path:** `~/Library/Group Containers/group.com.apple.usernoted/db2/db`, opened only as `file:<path>?mode=ro`. Never write to it.
- **Bundle ids:**
  - Teams: `com.microsoft.teams2`
  - Outlook alerts: `com.microsoft.outlook`
  - Outlook app to launch: `com.microsoft.Outlook`
  - Teams app to launch: `com.microsoft.teams2`
- **Cocoa reference dates:** `Date(timeIntervalSinceReferenceDate:)`.
- **Teams card:**
  - id: `teams:<messageId>`, or `teams:<uuidHex>` when there is no message id;
  - title: `Teams message`;
  - sender: `titl`; preview: `body`;
  - open URL, in this order:
    1. `msteams:/l/message/<convId>/<messageId>`
    2. `msteams:/l/chat/<convId>/0`
    3. `nil`, which launches Teams.
- **Mail card:**
  - id: `mail:<uuidHex>`;
  - title: `titl`; sender: `subt`; preview: `body`;
  - open URL: `nil`, which launches Outlook.
- **Event card:**
  - id: `"\(calendarItemExternalIdentifier ?? calendarItemIdentifier)@\(Int(start.timeIntervalSince1970))"`;
  - `webLink`: `ical://ekevent/<percent-encoded calendarItemIdentifier>?method=show&options=more`.
- **Meeting-link hosts** (the first match wins, searching `url`, then `location`, then `notes`):
  - `teams.microsoft.com/l/meetup-join/`
  - `teams.microsoft.com/meet/`
  - `zoom.us/j/` (any subdomain)
  - `webex.com/` (any subdomain)
  - `meet.google.com/`
- **First-launch window:** only alerts delivered in the last 24 h are ingested on the first launch.
- **Settings URLs:**
  - Full Disk Access: `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`
  - Calendar: `x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`
- **Info.plist** gains `NSCalendarsFullAccessUsageDescription` = `My Assistant shows today's meetings from your calendars.`
- **Old state files** must still decode. Unknown keys such as `deltaLinks` and `teamsLastSeen` are ignored.

## Review Focus

1. **A transient database error (`SQLITE_BUSY`, or locked during a WAL checkpoint)** must not switch the status to "Full Disk Access needed", and must not drop any cards. Test: `NotificationWatcherTests.busyErrorKeepsStatusAndItems`.
2. **An alert cleared in Notification Center after it was captured** must keep its card. Test: `NotificationWatcherTests.clearedRecordKeepsCard`.
3. **A Teams alert without a `convId` or `messageId`** (a reaction or meeting alert) must still produce a card, using the fallback ids and links. Tests: `AlertMapperTests.teamsWithoutIDsFallsBack` and `teamsChatOnlyUsesChatLink`.
4. **Occurrences of a recurring meeting** must get distinct ids. Dismissing one must not hide the others. Test: `CalendarMappingTests.recurringOccurrencesHaveDistinctIDs`.
5. **Day rollover:** a read just after midnight must query the new day. Test: `CalendarMappingTests.dayRangeFollowsNow`.

---

## File Structure

```
Sources/MyAssistantCore/
  Local/NotificationDatabase.swift  read-only SQLite access → [AlertRecord]; NotificationDBError
  Local/AlertRecord.swift           AlertRecord + parse(data:) from the record plist
  Local/AlertMapper.swift           pure AlertRecord → AssistantNotification
  Local/NotificationWatcher.swift   file watch + timer → reader → store; status
  Local/CalendarReader.swift        EventKit access; EKEvent → EventSnapshot
  Local/CalendarMapping.swift       pure EventSnapshot → CalendarEvent, meeting-link regex, day range
  Local/SourceCoordinator.swift     owns watcher + calendar reader; start/stop/restart; replaces Poller
  Sources/Source.swift              SourceStatus only (protocols removed)
  DELETE: Graph/*, Sources/{MailSource,TeamsSource,CalendarSource,Poller}.swift
Tests/MyAssistantTests/
  NotificationDatabaseTests.swift, AlertMapperTests.swift, NotificationWatcherTests.swift,
  CalendarMappingTests.swift, SourceCoordinatorTests.swift
  DELETE: GraphClientTests.swift, SourcesTests.swift (+ Graph cases in FinalFixTests/SettingsTests)
```

---

### Task 1: Notification database reader, plus a DEBUG dump

**Files:**
- Create: `Local/NotificationDatabase.swift`, `Local/AlertRecord.swift`, `Tests/MyAssistantTests/NotificationDatabaseTests.swift`
- Modify: `Sources/MyAssistant/MyAssistantApp.swift` (DEBUG menu item "Dump sources")

**Interfaces:**
- Produces:
  - `public struct AlertRecord: Equatable, Sendable { uuidHex: String; bundleID: String; delivered: Date; title: String?; subtitle: String?; body: String?; category: String?; archivedStrings: [String] }`
  - `static func parse(uuid: Data, bundleID: String, deliveredRef: Double, data: Data) -> AlertRecord?`
    - Parses `req.titl`, `subt`, `body`, `cate`.
    - `archivedStrings` holds every `String` in `usda`'s NSKeyedArchiver `$objects`. A `usda` that is missing or can't be parsed gives `[]`.
  - `public enum NotificationDBError: Error, Equatable { case accessDenied, busy, failed(Int32) }`
  - `public struct NotificationDatabase: Sendable { init(path: String = default); func read(bundleIDs: [String]) throws(NotificationDBError) -> [AlertRecord] }`
    - Opens with `sqlite3_open_v2(uri, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI)`, then queries, then closes.
    - Sorted newest first.
    - Error mapping:
      - `SQLITE_BUSY` and `SQLITE_LOCKED` → `.busy`;
      - `SQLITE_CANTOPEN` and `SQLITE_AUTH`, or a parent directory that can't be listed → `.accessDenied`;
      - anything else → `.failed(code)`.

- [ ] **Step 1: Write the failing tests.** Each test builds a temporary SQLite database with the real schema: `app(app_id INTEGER PRIMARY KEY, identifier TEXT)` and the `record` table from the spec.
  - Insert the record plist with `PropertyListSerialization` (binary). Build `usda` with `NSKeyedArchiver.archivedData(withRootObject: ["view": "{\"actionType\":\"view\",\"messageId\":\"1793626351355\"}", "chat": "19:abc_def@unq.gbl.spaces"], requiringSecureCoding: false)`.
  - `readsTeamsRecord`: title `"Doe, Jane"`; body `"ok. see you"`; `archivedStrings` contains the JSON string and `"19:abc_def@unq.gbl.spaces"`; `delivered == Date(timeIntervalSinceReferenceDate: 815319151)`.
  - `filtersByBundleID`: an `com.apple.mail` record is excluded.
  - `newestFirst`.
  - `corruptPlistSkipsRecordOnly`: two records, one with garbage `data`. The result has 1 record.
  - `missingFileIsAccessDenied`: a path in a nonexistent directory gives `.accessDenied`.
- [ ] **Step 2: Run** `swift run MyAssistantTests --filter NotificationDatabaseTests`. Expected: FAIL to compile.
- [ ] **Step 3: Implement.** Use `import SQLite3`.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Add the DEBUG "Dump sources" menu item.** It logs through `os.Logger(subsystem: "de.sebastiangross.MyAssistant", category: "diagnostics")`.
  - For each of the last 5 records per bundle: the category, whether `title`, `subtitle` and `body` are present (as Bool), and whether `convId` and `messageId` are found in `archivedStrings`.
  - Never log any content.
  - The event part is added in Task 4.
- [ ] **Step 6: Full suite plus bundle.** Run `swift run MyAssistantTests` (PASS) and `./scripts/bundle.sh` (builds).
- [ ] **Step 7: Commit:** `feat: read macOS notification database`.

### Task 2: Alert mapper

**Files:**
- Create: `Local/AlertMapper.swift`, `Tests/MyAssistantTests/AlertMapperTests.swift`

**Interfaces:**
- Consumes: `AlertRecord` from Task 1, and `AssistantNotification` and `SourceKind` (existing).
- Produces:
  - `public enum AlertMapper`
  - `static func map(_ r: AlertRecord) -> AssistantNotification?` returns `nil` for an unknown bundle.
  - `static func teamsIDs(_ strings: [String]) -> (convId: String?, messageId: String?)`
    - Parses the JSON strings for `convId` and `messageId`.
    - Falls back to any plain string matching `^19:` for `convId`.
  - `static func isFresh(_ r: AlertRecord, now: Date) -> Bool` returns `now - delivered <= 24 h`.

- [ ] **Step 1: Write the failing tests**, using the values in Global Constraints:
  - `teamsFullMapping`: id `teams:1793626351355`, title `Teams message`, sender, preview, URL `msteams:/l/message/19%3Aabc_def%40unq.gbl.spaces/1793626351355`.
    - Use percent-encoding with `.urlPathAllowed` minus `:@/`. Assert the exact string.
  - `teamsChatOnlyUsesChatLink`.
  - `teamsWithoutIDsFallsBack`: id `teams:<uuidHex>`, `openURL == nil`.
  - `outlookMapping`: id `mail:<uuidHex>`, title from `titl`, sender from `subt`, `openURL == nil`.
  - `unknownBundleIsNil`.
  - `freshnessWindow`: 23 h 59 min counts as fresh; 24 h 1 min does not.
- [ ] **Step 2: Run** `--filter AlertMapperTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit:** `feat: map Teams and Outlook alerts to notifications`.

### Task 3: Notification watcher

**Files:**
- Create: `Local/NotificationWatcher.swift`, `Tests/MyAssistantTests/NotificationWatcherTests.swift`
- Modify: `Sources/Source.swift`
  - Replace the contents with: `public enum SourceStatus: Equatable, Sendable { case disabled, ok(Date), noAlertsYet, needsFullDiskAccess, needsCalendarAccess, error(String) }`
  - Delete the protocols and `GraphSourceSet`. Their users are deleted in Task 5. Until then, keep the build green by moving the old protocol declarations to the top of `Poller.swift`.
- Modify: `Stores/Persistence.swift`: add `public var alertsBootstrapped = false` to `PersistedState`, decoding to `false` when the key is missing.

**Interfaces:**
- Consumes: `NotificationDatabase`/`NotificationDBError` (Task 1), `AlertMapper` (Task 2), `AppModel` (existing: `notifications.ingest`, `status`, `state`, `save()`).
- Produces: `@MainActor public final class NotificationWatcher`, with:
  - `init(model: AppModel, read: @escaping @Sendable ([String]) throws(NotificationDBError) -> [AlertRecord], now: @escaping () -> Date = Date.init)`
  - `func start()` and `func stop()`
  - `func readNow()`
- `readNow()` behaviour:
  1. Reads the enabled bundles: `.teams` gives `com.microsoft.teams2` and `.mail` gives `com.microsoft.outlook`.
  2. While `!state.alertsBootstrapped`, it ingests only fresh records, then sets the flag and calls `save()`.
  3. It ingests the mapped records.
  4. It sets the status for each kind:
     - `.ok(now)` once that kind has had a record since launch, otherwise `.noAlertsYet`;
     - `.needsFullDiskAccess` on `.accessDenied`;
     - unchanged on `.busy`;
     - `.error("Notification database error <code>")` on `.failed`.
- `start()` sets up:
  - `DispatchSource` file watchers on `db` and `db-wal` (`.write, .extend, .rename, .delete`), re-armed after rename or delete, with a 300 ms debounce;
  - a 5 s repeating timer;
  - an immediate `readNow()`.

- [ ] **Step 1: Write the failing tests.** Use an in-memory `AppModel` (temporary persistence) and a fake `read` closure.
  - `ingestsTeamsAndMail`
  - `bootstrapOnlyIngestsFresh`: a 30 h-old record is skipped on the first read. On the second read, after `alertsBootstrapped`, it is ingested.
  - `clearedRecordKeepsCard`: read 1 returns the record, read 2 returns `[]`, and the card is still in `notifications.visible`.
  - `busyErrorKeepsStatusAndItems`
  - `accessDeniedSetsStatus`
  - `disabledSourceNotRead`: with `.mail` turned off, the read is called with only the Teams bundle, and the status for `.mail` is `.disabled`.
  - `noAlertsYetUntilFirstRecord`
- [ ] **Step 2: Run** `--filter NotificationWatcherTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit:** `feat: watch notification database for new alerts`.

### Task 4: Calendar reader

**Files:**
- Create: `Local/CalendarMapping.swift`, `Local/CalendarReader.swift`, `Tests/MyAssistantTests/CalendarMappingTests.swift`
- Modify: `Resources/Info.plist`: add the usage string from Global Constraints.
- Modify: the DEBUG "Dump sources" item. Add the count of today's events and, for each event, whether `url`, `location`, `notes` and a meeting link are present, whether an organizer exists, and the current user's participant status. No content.

**Interfaces:**
- Produces:
  - `public struct EventSnapshot: Sendable { itemID: String; externalID: String?; title: String; start: Date; end: Date; isAllDay: Bool; location: String?; notes: String?; url: URL?; organizer: String?; canceled: Bool; declinedByMe: Bool }`
  - `public enum CalendarMapping`, with:
    - `static func dayRange(now: Date, calendar: Calendar) -> (start: Date, end: Date)`
    - `static func meetingLink(url: URL?, location: String?, notes: String?) -> URL?`
    - `static func map(_ s: EventSnapshot) -> CalendarEvent?` returns `nil` when `canceled` or `declinedByMe`.
  - `@MainActor public final class CalendarReader`, with:
    - `init(model: AppModel, store: EKEventStore = .init(), now: @escaping () -> Date = Date.init)`
    - `func start()`, `func stop()`
    - `func refresh() async`
  - Behaviour:
    - It requests full access once.
    - If access is denied, it sets `.needsCalendarAccess`.
    - On success it calls `events.replace(mapped)` and sets `.ok(now)`.
    - It listens to `.EKEventStoreChanged`, debounced 1 s.
    - It refreshes every 60 s and at the next midnight.
    - `declinedByMe` is true when `attendees` contains a participant where `isCurrentUser` and `participantStatus == .declined`.

- [ ] **Step 1: Write the failing tests:**
  - `mapsBasicEvent`: id format; `webLink == URL(string: "ical://ekevent/ABC%2F123?method=show&options=more")` for `itemID` `"ABC/123"`.
  - `teamsLinkFromNotes`: notes containing `"Join: https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%7d\n"` give that exact URL, with no trailing newline.
  - `urlFieldWinsOverNotes`
  - `zoomAndMeetLinks`
  - `noLinkIsNil`
  - `canceledAndDeclinedDropped`
  - `recurringOccurrencesHaveDistinctIDs`: same `externalID`, different starts, different ids.
  - `dayRangeFollowsNow`: `now` at 2026-11-03 00:01 Europe/Berlin gives a range starting 2026-11-03 00:00 and ending 2026-11-04 00:00.
- [ ] **Step 2: Run** `--filter CalendarMappingTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** Use `NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)` and take the first link whose host and path match the host list.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Bundle and smoke test.** Run `./scripts/bundle.sh`. Confirm that `plutil -p "build/My Assistant.app/Contents/Info.plist"` shows the key.
- [ ] **Step 6: Commit:** `feat: read today's events from EventKit`.

### Task 5: Coordinator, wiring, and Graph removal

**Files:**
- Create: `Local/SourceCoordinator.swift`, `Tests/MyAssistantTests/SourceCoordinatorTests.swift`
- Delete:
  - `Graph/` (all of it)
  - `Sources/MailSource.swift`, `Sources/TeamsSource.swift`, `Sources/CalendarSource.swift`, `Sources/Poller.swift`
  - `Tests/MyAssistantTests/GraphClientTests.swift`, `Tests/MyAssistantTests/SourcesTests.swift`
  - the Graph and OAuth cases in `FinalFixTests.swift` and `SettingsTests.swift`
- Modify:
  - `App/AppModel.swift`: remove `oauth`, `rebuildOAuth`, `clearSyncState` and the `transport` init parameter.
  - `Stores/Persistence.swift`: remove `clientID`, `tenantID`, `deltaLinks` and `teamsLastSeen`. Decoding ignores those keys.
  - `UI/SettingsController.swift`: remove the account and sign-in logic, and the poller hook. Replace it with `restartSources: @MainActor () -> Void`.
  - `Sources/MyAssistant/MyAssistantApp.swift`: replace `Poller` with `SourceCoordinator`.

**Interfaces:**
- Consumes: `NotificationWatcher` (Task 3) and `CalendarReader` (Task 4).
- Produces: `@MainActor public final class SourceCoordinator`, with:
  - `init(model: AppModel, watcher: NotificationWatcher, calendar: CalendarReader)`
  - `func start()`: starts the watcher if `.teams` or `.mail` is enabled, and the calendar reader if `.calendar` is enabled. Otherwise it sets `.disabled`.
  - `func stop()`
  - `func restart()`: stop, then start.
  - On `NSWorkspace.didWakeNotification`, it calls `watcher.readNow()` and `await calendar.refresh()`.

- [ ] **Step 1: Write the failing tests:**
  - `SourceCoordinatorTests.disabledCalendarNotStarted`: the status is `.disabled`.
  - `restartAppliesToggles`.
  - `SettingsTests.oldStateWithGraphKeysDecodes`: JSON containing `clientID`, `deltaLinks` and `teamsLastSeen` decodes, and the other values are kept.
- [ ] **Step 2: Run** `--filter SourceCoordinatorTests`. Expected: FAIL.
- [ ] **Step 3: Implement, delete and rewire.** `grep -rn "Graph\|OAuth\|Poller\|clientID\|deltaLinks\|teamsLastSeen" Sources Tests` must print nothing.
- [ ] **Step 4: Full suite plus bundle.** `swift run MyAssistantTests` passes. `./scripts/bundle.sh` builds. The app launches and stays alive for 5 s.
- [ ] **Step 5: Commit:** `refactor: replace Graph sources with local sources`.

### Task 6: Settings Sources tab and README

**Files:**
- Modify:
  - `UI/SettingsView.swift`: delete the Accounts tab. The Sources tab is the first tab.
  - `UI/SettingsController.swift`: add `func openFullDiskAccessSettings()` and `func fixCalendarAccess() async`. Calendar access means: request it when the status is not yet determined, otherwise open the Calendar privacy settings.
  - `README.md`: replace the Entra and Graph setup sections.
- Test: `Tests/MyAssistantTests/SettingsTests.swift`

**Interfaces:**
- Consumes: `SourceStatus` (Task 3), `SourceCoordinator.restart()` (Task 5).
- Produces: none.

- [ ] **Step 1: Write the failing tests.** Inject the opener closure and record which URL each fix opens:
  - `SettingsTests.fullDiskAccessButtonOpensPrivacyAllFiles`
  - `calendarFixOpensSettingsWhenDenied`
  - `toggleRestartsSources`
- [ ] **Step 2: Run** `--filter SettingsTests`. Expected: FAIL.
- [ ] **Step 3: Implement the UI.** One `Form` section for each of Teams, Outlook mail and Calendar. Each has:
  - a toggle;
  - a status line: `Working · updated <relative time>` / `Full Disk Access needed` / `Calendar access needed` / `No alerts seen yet` / the error text;
  - a fix button where relevant.

  The footer carries the exact hint text from the spec.
- [ ] **Step 4: Update the README.** Cover:
  - granting Full Disk Access and Calendar access to `My Assistant.app`;
  - turning on Teams and Outlook notifications;
  - adding the Exchange account in Internet Accounts;
  - the rebuild note.
- [ ] **Step 5: Run the full suite** (PASS), **bundle, and launch.** Then do the manual checks with the user. Record their results in the report:
  - a Teams message shows up within about 2 s, and clicking it opens the chat;
  - a test mail shows up, and clicking it opens Outlook;
  - today's meetings appear, clicking one opens it in Calendar, and Join opens Teams.
- [ ] **Step 6: Commit:** `feat: local sources settings and docs`.
