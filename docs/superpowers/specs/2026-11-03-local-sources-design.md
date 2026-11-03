# My Assistant — Local Sources Redesign

**Date:** 2026-11-03
**Replaces:** the Microsoft Graph integration from `docs/superpowers/plans/2026-11-03-my-assistant.md` (Tasks 7, 8 and the account part of Task 10).

## Intent

The user cannot register an Entra ID app in the corporate tenant, so the app cannot use Microsoft Graph. Instead, My Assistant reads data the Mac already has:

- **Teams and Outlook mail:** the alerts these apps post to macOS.
- **Calendar:** the Exchange account the user added under System Settings → Internet Accounts.

There is no sign-in and no network access. Everything the user sees stays the same: the docked panel, notification cards, snooze, the countdown, and Settings.

## Goals

- New Teams messages and Outlook mails appear as cards within about 2 s of macOS receiving the alert.
- Clicking a Teams card opens the exact chat at that message. Clicking a mail card opens Outlook.
- Today's events come from macOS Calendar (EventKit), including the Exchange account. They update when the calendar changes.
- Join opens the meeting link found in the event.
- Settings shows whether each source works, and offers one-click fixes for missing permissions.

## Non-goals

- Opening the exact mail. The alert only carries Outlook's internal binary message ID, which can't be used in a link.
- Marking a mail as read, or replying.
- Clearing the macOS alert when a card is done. The two lists are independent.
- Keeping the Graph code. It is deleted (user's choice: local-only).

## Anti-goals

- Writing to the notification database in any way. Access is read-only.
- Prompting for permissions in a loop, or before the user can see why they're needed.

## Constraints and facts verified on this Mac (macOS 27.0.1)

### Notification database

- **Location:** `~/Library/Group Containers/group.com.apple.usernoted/db2/db`, an SQLite database in WAL mode. Reading it needs **Full Disk Access**.
  - It can be read with `file:<path>?mode=ro` (URI). This was tested and works while the database is in use.
- **Tables:**
  - `app(app_id, identifier)`
  - `record(rec_id, app_id, uuid BLOB, data BLOB, request_date, request_last_date, delivered_date REAL, presented, style, snooze_fire_date)`
- **Dates** are Cocoa reference dates: seconds since 2001-01-01 UTC.
- **`record.data`** is a binary plist. The fields used:
  - `req.titl`, `req.subt`, `req.body`: strings.
  - `req.usda`: a binary plist in NSKeyedArchiver format.
  - `req.cate`: category.
  - `req.iden`: notification id.
- **Teams** (`com.microsoft.teams2`):
  - `titl` is the sender name. `body` is the message text. `subt` is usually empty.
  - The `$objects` in `usda` contain JSON strings such as `{"actionType":"view","messageId":"1793626351355",...}` and `{"actionType":"quickReply","convId":"19:…",...}`.
  - The chat id `19:…` also appears as a plain string.
- **Outlook** (`com.microsoft.outlook`, new Outlook):
  - `titl` is the subject. `subt` is the sender name. `body` is the preview.
  - `usda` holds a binary message server id that can't be used for a link.
- **Records disappear** when the user clears the alert in Notification Center. The app must read records as they arrive, and must keep cards it has already captured.
- **Outlook alerts** only exist if notifications are enabled for Outlook, both in macOS and inside Outlook. The user has enabled them and confirmed they arrive.

### Calendar

- EventKit, with `requestFullAccessToEvents`. The Info.plist needs `NSCalendarsFullAccessUsageDescription`.
- The Exchange account is active.
- I could not check the event contents from the command line, because a script can't show the permission prompt. That has to be checked inside the app (see the Review Focus in the plan).

### Build

- Command Line Tools only. Tests run with `swift run MyAssistantTests`. Use the system `SQLite3` module (`import SQLite3`). No third-party dependencies.

## Approaches considered

| Approach | Trade-off | Decision |
|---|---|---|
| **A. Watch the notification database** | Catches every alert, even during Do Not Disturb or with banners off. Gets Teams chat ids. Needs Full Disk Access, and the format is undocumented, so a macOS update may need a reader fix. | **Chosen** |
| B. Read the on-screen banners via Accessibility | No Full Disk Access needed. But it misses alerts during Do Not Disturb or with banners off, gets no ids, and breaks when the banner layout changes. | Rejected |
| Keep Graph switchable | Dead code without an app registration. | Rejected (user chose local-only) |
| Calendar via Outlook AppleScript | The new Outlook returns 0 events and 0 messages to AppleScript (verified). | Rejected |
| Calendar via an ICS publish link | Works without an account in macOS, but the user chose an Exchange account. | Rejected |

## Design

### NotificationDatabase (reader)

- Opens the database read-only for each read: open, query, close. This avoids holding locks.
- **Query:** join `record` to `app`, filtered to `identifier IN ('com.microsoft.teams2','com.microsoft.outlook')`, newest first.
- **Parsing:** each row becomes an `AlertRecord`:
  - `uuid` as a hex string
  - `bundleID`
  - `delivered` as a `Date`
  - `title`, `subtitle`, `body`
  - `archivedStrings`: all strings from the `usda` `$objects`
- **Mapping is pure and testable**, so tests work from fixture plists rather than a live database.
  - **Teams:**
    - The id is `teams:<messageId>`, or `teams:<uuid>` if there is no message id.
    - The sender comes from `title`. The preview is `body`. The title is "Teams message".
    - `openURL` is `msteams:/l/message/<convId>/<messageId>`, with each part percent-encoded.
    - If there is a chat id but no message id, use `msteams:/l/chat/<convId>/0`. If neither exists, use `nil`; the open action then launches Teams.
  - **Outlook:**
    - The id is `mail:<uuid>`.
    - The title is `title` (subject). The sender is `subtitle`. The preview is `body`.
    - `openURL` is `nil`; the open action launches Outlook (`com.microsoft.Outlook`).
  - `firstSurfacedAt` and `surfacedAt` are both `delivered`.
- **Errors:**
  - If the database can't be opened, or it fails with a permission error, report `.needsFullDiskAccess`.
  - A parse failure on one record skips that record. It doesn't fail the batch.

### NotificationWatcher

- Watches `db` and `db-wal` with `DispatchSource.makeFileSystemObjectSource` (`.write`, `.extend`, `.rename`, `.delete`). It re-arms the source after a rename or delete.
- Changes are batched with a 300 ms debounce. A 5 s timer also triggers a read, as a safety net.
- **On each read:** map the records and pass them to `NotificationStore.ingest`. Ingest already ignores IDs that are on the list or already handled.
- **First launch:** only alerts from the last 24 h are ingested. After that, everything still in the database is ingested, and ingest drops duplicates.
- **Per-source enable toggles** (Teams, Outlook) filter by bundle id.

### CalendarReader

- Uses `EKEventStore`. It asks for full access on first use. Status: `.needsCalendarAccess` when access is denied.
- **What it reads:** today's events, `[startOfDay, startOfDay + 1d)`, from all event calendars.
- **What it drops:**
  - cancelled events (`status == .canceled`);
  - events where the current user's participant status is `.declined`;
  - all-day events (the existing `EventStore` rule).
- **Mapping to `CalendarEvent`:**
  - The id is `calendarItemExternalIdentifier ?? calendarItemIdentifier`, plus `@`, plus the start time as a Unix integer. This keeps each occurrence of a recurring meeting distinct.
  - `subject`, `start`, `end` and `location` map directly. `organizer` is the organizer's name.
  - `joinURL` is the first match of the meeting-link regex. It searches `url`, `location` and `notes`, in that order. Matched hosts:
    - `teams.microsoft.com/l/meetup-join/…`
    - `teams.microsoft.com/meet/…`
    - `*.zoom.us/j/…`
    - `*.webex.com/…`
    - `meet.google.com/…`
  - `webLink` is the open-event target (see Decided).
- **Refresh triggers:**
  - `EKEventStoreChanged`, debounced by 1 s;
  - a 60 s timer;
  - midnight.

### Settings changes

- **The Accounts tab is removed** (client ID, tenant ID, sign-in).
- **The Sources tab** shows one row for each of Teams, Outlook mail and Calendar. Each row has:
  - an on/off toggle;
  - a status: OK with the last update time, *Full Disk Access needed*, *Calendar access needed*, or *No alerts seen yet*;
  - a fix button, where relevant:
    - Full Disk Access: open `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`;
    - Calendar: request access, or open `…?Privacy_Calendars` if access was denied.
- **Hint:** "Turn on notifications for Outlook and Teams in System Settings → Notifications (banners may be set to None; alerts still arrive)."
- **The General tab** is unchanged.

### Removed

- `Graph/*`
- `Sources/MailSource.swift`, `Sources/TeamsSource.swift` and the Graph `CalendarSource`
- The Graph part of `Poller`
- The OAuth part of `SettingsController`
- Graph-specific `PersistedState` fields. Old state files must still decode; unknown keys are ignored.
- The Keychain wrapper
- The README sections about Entra and Graph

## Decided

1. **Where an event opens when clicked** (user decision): macOS Calendar, showing that event. `webLink` is `ical://ekevent/<calendarItemIdentifier>?method=show&options=more`, with the identifier percent-encoded.
   - This URL is not officially documented, so it needs a manual check.
   - If Calendar doesn't accept it for Exchange items, the fallback is to open the Calendar app on today's date.

## Calls made during the builder check (my calls unless noted)

- **Verify the data first.** The first implementation task adds a DEBUG-only "Dump sources" menu item. It logs, redacted, the field names and the presence of `url`, `location`, `notes`, a meeting-link match, the organizer and the current user's participant status for today's events. It also lists Teams alert categories and whether `convId` and `messageId` are present.
  - The Join and click-open designs are confirmed against this output before the mapping code is final.
  - If `notes` contain no join link, Join stays hidden for that event, which is the existing behaviour.
- **Teams alerts without a `messageId`** (mentions, reactions, meeting alerts) use the chat link (`msteams:/l/chat/<convId>/0`). Without a `convId`, clicking opens Teams.
  - The `msteams:/l/message/…` link format is treated as unverified until checked by hand. The fallback order is fixed.
- **Duplicates and persistence** are already handled. `handledIDs` persists across relaunches and is capped at 5000. The record UUID is stable while the record exists. Edited Teams messages don't post new alerts.
- **App identity.** The app runs as the bundle built by `./scripts/bundle.sh` (`de.sebastiangross.MyAssistant`), and its `Info.plist` gains `NSCalendarsFullAccessUsageDescription`.
  - Ad-hoc rebuilds reset Full Disk Access and Calendar grants (already noted in the README). The user grants them to `build/My Assistant.app`, or to the copy in `/Applications`.
- **Status semantics:**
  - **Full Disk Access needed:** the `db2` directory can't be listed (`EPERM`) or SQLite fails to open the file.
  - **No alerts seen yet:** the database is readable, but no record from that app has been seen since launch.
  - **OK:** at least one record has been read, or the database was read successfully and the source has delivered before. The status shows the time of the last successful read.
- **Upgrading from the Graph version.** Existing cards and handled IDs are kept as they are, since their web links still work. The 24 h first-launch window applies to the new database watcher whatever the old state was.

## Left to the builder

- Whether `Poller` becomes a small `SourceCoordinator`, or the watcher and reader are owned directly by `AppModel`.
- The exact debounce and timer values within the ranges above.
- The SQLite helper style.
