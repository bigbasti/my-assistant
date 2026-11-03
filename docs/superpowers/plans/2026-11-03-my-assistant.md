# My Assistant (macOS Docked Assistant) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS app that stays docked on the left or right edge of a screen, always on top, and shows Teams and Outlook notifications (top half) and today's calendar (bottom half) with snooze, dismiss and join actions.

**Architecture:** This is a SwiftUI app built with SwiftPM and hosted in a borderless, non-activating `NSPanel` at a high window level. One `AppModel` (`@Observable`) owns the stores for notifications and events. These stores get data from source adapters that use Microsoft Graph, polled with delta queries. Graph webhooks need a public HTTPS endpoint, so a local app can't receive them. A `ScreenReserver` uses the Accessibility API to push other windows out of the docked strip. That's needed because macOS has no public "app bar" API for reserving screen space.

**Tech Stack:** Swift 6.3, SwiftUI + AppKit (macOS 26+ for the Liquid Glass `glassEffect`), Swift Testing, `URLSession`, `ASWebAuthenticationSession` (OAuth 2.0 auth code + PKCE, with no MSAL dependency), Keychain, `SMAppService` for launch at login, and `UserNotifications`/`NSSound` for the tone. Builds with the Command Line Tools only (`swift build`, no Xcode).

**Spec:** The user request in this session (no separate spec). The integration design decisions are recorded below.

### Integration decisions (brainstormed)
| Source | Access | Freshness |
|---|---|---|
| Outlook Mail | Graph `GET /me/mailFolders/inbox/messages/delta` (`Mail.Read`) | Poll the delta link every 30 s |
| Outlook Calendar | Graph `GET /me/calendarView/delta?startDateTime=…&endDateTime=…` (`Calendars.Read`) for today | Poll every 60 s and at midnight |
| Teams chats | Graph `GET /me/chats/getAllMessages` is app-only, so use `GET /me/chats?$expand=lastMessagePreview&$orderby=lastMessagePreview/createdDateTime desc` (`Chat.Read`) | Poll every 20 s, and emit a notification when `lastMessagePreview.id` changes and the sender is not the current user |

- Auth: one Entra ID app registration, set up as a public client with redirect `myassistant://auth`. The user enters the Client ID and Tenant ID in Settings. **Risk:** corporate tenants may require admin consent for `Chat.Read`. In that case the Teams source shows "consent required" and the other sources keep working.
- Open actions: a message opens its `webLink`. A chat opens `msteams:/l/chat/0/0?users=…`, or the chat's `webUrl` as a fallback. An event opens its `webLink`. Join opens `onlineMeeting.joinUrl` (the Teams client handles `https://teams.microsoft.com/l/meetup-join/…` links). If there's no join URL, the join button is hidden.

## Global Constraints
- Minimum macOS version: `.macOS(.v26)`. No third-party dependencies.
- Bundle ID: `de.sebastiangross.MyAssistant`. App name: `My Assistant`.
- Dock width is fixed at `360` pt. Edges: `.left`, `.right`.
- Snooze options, with these exact labels: "in 10 Min", "in 30 Min", "in 1 Hour", "in 3 Hours", "Tomorrow", "Custom…". "Tomorrow" means the same time of day as `firstSurfacedAt`, plus 1 day.
- Only "Done" (checkmark) and snooze remove a notification. Clicking a notification never removes it.
- Notifications are sorted by `surfacedAt` (newest first). Events are sorted by `start` (soonest first). Past events are hidden after they end.
- Countdown thresholds: show the timer at `< 10 min`, turn red at `<= 5 min`, pulse at `< 1 min`, and at start stop pulsing, stay red and play the tone once.
- Source colors: Teams `#6264A7`, Mail `#0078D4`, Calendar `#0F9D58`.
- Tokens are stored only in the Keychain. Settings and state are stored in `~/Library/Application Support/MyAssistant/state.json`.

## Review Focus
1. **Duplicate notifications after a restart or a repeated delta.** A message ID that has already been seen (dismissed or snoozed) must never come back. Test: `NotificationStoreTests.ingestingKnownIdIsIgnored`.
2. **Snoozed item due while the app was closed.** On launch it must reappear right away, at the top. Test: `NotificationStoreTests.overdueSnoozeResurfacesOnLoad`.
3. **The tone plays more than once** (re-render, poll refresh, or the event updated by delta). Test: `EventTimerTests.toneFiresOnceAcrossRefreshes`.
4. **Expired refresh token or network loss.** The source shows an error badge, keeps the existing items and keeps retrying with backoff, and the UI doesn't crash. Test: `GraphClientTests.unauthorizedTriggersRefreshThenSurfacesError`.
5. **The docked screen is unplugged.** The panel moves to the main screen on the same edge. Test: `DockGeometryTests.missingScreenFallsBackToMain`.

---

## File Structure
```
Package.swift
Sources/MyAssistant/
  App/MyAssistantApp.swift        @main, MenuBarExtra + Settings scene, AppDelegate
  App/AppModel.swift              @Observable root; wires stores, sources, timers
  Dock/DockGeometry.swift         pure frame math (testable)
  Dock/DockPanel.swift            NSPanel subclass + DockController (drag, snap, edge preview)
  Dock/ScreenReserver.swift       AX observer that pushes other windows out of the strip
  Model/AssistantNotification.swift
  Model/CalendarEvent.swift
  Model/SnoozeOption.swift
  Stores/NotificationStore.swift
  Stores/EventStore.swift
  Stores/Persistence.swift
  Graph/OAuth.swift               PKCE + ASWebAuthenticationSession + refresh
  Graph/Keychain.swift
  Graph/GraphClient.swift         authorized GET, delta paging, 401/429 handling
  Sources/Source.swift            protocol + SourceKind + SourceStatus
  Sources/MailSource.swift
  Sources/CalendarSource.swift
  Sources/TeamsSource.swift
  Sources/Poller.swift
  UI/RootView.swift               split view, glass background
  UI/NotificationCard.swift
  UI/SnoozeSheet.swift
  UI/EventCard.swift
  UI/EventTimer.swift             countdown state machine (pure)
  UI/SettingsView.swift
  System/LaunchAtLogin.swift
  System/Opener.swift             NSWorkspace URL opening
Tests/MyAssistantTests/…          one file per tested unit
scripts/bundle.sh                 swift build -c release → My Assistant.app (Info.plist, URL scheme, ad-hoc sign)
Resources/Info.plist, Resources/chime.aiff
```

---

### Task 1: Package skeleton, app bundle and menu bar

**Files:** Create `Package.swift`, `App/MyAssistantApp.swift`, `scripts/bundle.sh`, `Resources/Info.plist`, `Tests/MyAssistantTests/SmokeTests.swift`

**Interfaces:**
- Produces: the executable target `MyAssistant`, and the test target `MyAssistantTests` with `@testable import MyAssistant`. To keep tests possible, split the code into a library target `MyAssistantCore` (all sources except `@main`) and a thin executable `MyAssistant`.

- [ ] **Step 1:** Write `SmokeTests.versionIsSet`, which asserts `AppInfo.version == "0.1.0"`.
- [ ] **Step 2:** Run `swift test`. Expected: FAIL (`AppInfo` undefined).
- [ ] **Step 3:** Create the package and `enum AppInfo { static let version = "0.1.0" }`. In `@main`, add `MenuBarExtra("My Assistant", systemImage: "sparkles")` with the items "Settings…" (`SettingsLink`), "Dock Left", "Dock Right" and "Quit", plus a `Settings { SettingsView() }` placeholder. Set `NSApp.setActivationPolicy(.accessory)`. Info.plist needs `LSUIElement=true`, `CFBundleURLTypes` with scheme `myassistant`, and `NSAppleEventsUsageDescription`. In `bundle.sh`, build the release, assemble `build/My Assistant.app`, copy the resources and run `codesign -s - --force`.
- [ ] **Step 4:** Run `swift test` (PASS), then `./scripts/bundle.sh && open "build/My Assistant.app"`. Expected: a menu bar icon appears.
- [ ] **Step 5:** Run `git init`, then commit: `feat: package skeleton and menu bar`.

### Task 2: Dock geometry (pure)

**Files:** Create `Dock/DockGeometry.swift` and `Tests/.../DockGeometryTests.swift`

**Interfaces:**
- Produces: `enum DockEdge: String, Codable { case left, right }`; `struct DockPlacement: Codable, Equatable { var screenID: CGDirectDisplayID; var edge: DockEdge }`; `enum DockGeometry { static let width: CGFloat = 360; static func frame(for edge: DockEdge, in visibleFrame: CGRect) -> CGRect; static func nearestPlacement(dropPoint: CGPoint, screens: [(id: CGDirectDisplayID, visibleFrame: CGRect)]) -> DockPlacement; static func resolve(_ p: DockPlacement, screens: [(id: CGDirectDisplayID, visibleFrame: CGRect)], mainID: CGDirectDisplayID) -> (id: CGDirectDisplayID, frame: CGRect) }`

- [ ] **Step 1:** Write these tests: `leftFrame` (visible `(0,0,1440,875)` → `(0,0,360,875)`), `rightFrame` (→ `(1080,0,360,875)`), `secondScreenOffset` (visible `(1440,0,1920,1050)` right → `x == 3000`), `dropNearRightEdgeOfScreen2PicksScreen2Right`, `dropOnLeftHalfPicksLeft`, and `missingScreenFallsBackToMain` (Review Focus 5).
- [ ] **Step 2:** Run `swift test --filter DockGeometryTests`. Expected: FAIL.
- [ ] **Step 3:** Implement it. The screen is the one whose frame contains `dropPoint` (otherwise the nearest one by center distance). The edge is `.left` when `dropPoint.x < midX`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: dock geometry`.

### Task 3: Dock panel, drag to re-dock with preview, and screen reservation

**Files:** Create `Dock/DockPanel.swift` and `Dock/ScreenReserver.swift`. Modify `App/MyAssistantApp.swift`.

**Interfaces:**
- Consumes: `DockGeometry`, `DockPlacement`.
- Produces: `@MainActor final class DockController { init(content: some View); var placement: DockPlacement { get set }; func show(); func dock(to: DockPlacement, animated: Bool) }`, and `@MainActor final class ScreenReserver { func reserve(_ strip: CGRect?) }`, where `nil` turns reservation off.

- [ ] **Step 1:** Write `DockPanel: NSPanel` with `styleMask [.borderless, .nonactivatingPanel, .fullSizeContentView]`, `level = .statusBar`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`, `isMovableByWindowBackground = false`, `hidesOnDeactivate = false`, a clear background and `canBecomeKey = true` (so the snooze date picker works).
- [ ] **Step 2:** Add a drag handle (a 24 pt grip at the top of `RootView`, exposed through a `DockController.beginDrag(event:)` callback). During the drag the panel follows the mouse. A separate borderless `previewWindow` at `.statusBar - 1` shows a translucent accent-tinted rounded rect at `DockGeometry.frame(for: nearestPlacement(...))`. On mouse-up, hide the preview and call `dock(to:animated:true)` with `NSAnimationContext` at 0.25 s. Persist the placement through `Persistence` (Task 5). React to `NSApplication.didChangeScreenParametersNotification` by calling `resolve`.
- [ ] **Step 3:** `ScreenReserver`: if `AXIsProcessTrustedWithOptions` (prompt = true) is granted, observe `NSWorkspace.didActivateApplicationNotification` and add an `AXObserver` per app for `kAXWindowMovedNotification`, `kAXWindowResizedNotification` and `kAXWindowCreatedNotification`. For each standard window on the docked screen whose AX frame intersects the strip, set `kAXPositionAttribute`/`kAXSizeAttribute` so the window's frame equals the visible frame minus the strip. Skip our own PID and full-screen windows. Convert between AX coordinates (top-left origin) and Cocoa coordinates using the primary screen height. Add a helper `static func clamp(_ window: CGRect, avoiding strip: CGRect, in visible: CGRect) -> CGRect?` (pure, returns `nil` when no change is needed) and test it in `ScreenReserverTests`: `maximizedWindowIsShrunk`, `windowOutsideStripUntouched`, `windowOnRightDockGetsNarrowedFromRight`.
- [ ] **Step 4:** Run `swift test --filter ScreenReserverTests` (PASS). Then check by hand: bundle and launch the app, maximize Safari on the same screen and confirm it doesn't cover the panel; drag the panel to the right edge and the second screen and confirm the preview shows and it snaps there; unplug the screen and confirm it moves to the main screen.
- [ ] **Step 5:** Commit: `feat: always-on-top dock panel with edge snapping and screen reservation`.

### Task 4: Models and snooze math

**Files:** Create `Model/*.swift` and `Tests/.../SnoozeOptionTests.swift`

**Interfaces:**
- Produces:
  - `enum SourceKind: String, Codable, CaseIterable { case teams, mail, calendar }` with `var color: Color` (the hex values from Global Constraints).
  - `struct AssistantNotification: Identifiable, Codable, Equatable { let id: String /* "\(kind):\(graphId)" */; let kind: SourceKind; var title: String; var sender: String; var preview: String; var openURL: URL?; var firstSurfacedAt: Date; var surfacedAt: Date; var snoozedUntil: Date? }`
  - `struct CalendarEvent: Identifiable, Codable, Equatable { let id: String; var subject: String; var start: Date; var end: Date; var location: String?; var organizer: String?; var webLink: URL?; var joinURL: URL?; var isAllDay: Bool }`
  - `enum SnoozeOption: CaseIterable { case min10, min30, hour1, hour3, tomorrow; case custom(Date) }` with `var label: String` and `func resurfaceDate(now: Date, firstSurfacedAt: Date, calendar: Calendar) -> Date`.

- [ ] **Step 1:** Write tests: `labelsMatchSpec` (the exact strings), `min10AddsTenMinutes`, `hour3AddsThreeHours`, `tomorrowKeepsOriginalTimeOfDay` (`firstSurfacedAt` 09:42 on 3 Nov, now 16:00 → 09:42 on 4 Nov), `customReturnsGivenDate`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement it. The custom date picker in the UI defaults to the original time of day.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: models and snooze options`.

### Task 5: Persistence and NotificationStore

**Files:** Create `Stores/Persistence.swift`, `Stores/NotificationStore.swift` and `Tests/.../NotificationStoreTests.swift`

**Interfaces:**
- Produces:
  - `struct PersistedState: Codable { var notifications: [AssistantNotification]; var handledIDs: Set<String>; var dismissedEventIDs: Set<String>; var deltaLinks: [String: URL]; var teamsLastSeen: [String: String]; var dock: DockPlacement?; var settings: AppSettings }`
  - `struct AppSettings: Codable { var clientID = ""; var tenantID = "organizations"; var enabled: Set<SourceKind> = Set(SourceKind.allCases); var launchAtLogin = false; var reserveScreenSpace = true; var playTone = true }`
  - `final class Persistence { init(url: URL); func load() -> PersistedState; func save(_: PersistedState) }`
  - `@Observable @MainActor final class NotificationStore { init(state: PersistedState, now: @escaping () -> Date); var visible: [AssistantNotification] { get }; func ingest(_ items: [AssistantNotification]); func markDone(_ id: String); func snooze(_ id: String, _ option: SnoozeOption); func tick() }`. `visible` holds the non-snoozed items sorted by `surfacedAt` descending. `tick()` brings back snoozed items whose time has passed, sets `surfacedAt = now` and clears `snoozedUntil`.

- [ ] **Step 1:** Write tests: `newestOnTop`, `markDoneRemovesAndRemembers`, `snoozeHidesUntilDue`, `tickResurfacesAtTop`, `ingestingKnownIdIsIgnored` (Review Focus 1: both handled IDs and already-listed IDs), `overdueSnoozeResurfacesOnLoad` (Review Focus 2), `persistenceRoundTrip` (temp dir).
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement it. Debounce saves by 0.5 s. Cap `handledIDs` at 5,000 (trim the oldest by insertion order, keeping an array alongside the set).
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: notification store with persistence`.

### Task 6: EventStore and countdown state machine

**Files:** Create `Stores/EventStore.swift`, `UI/EventTimer.swift`, `Tests/.../EventStoreTests.swift` and `Tests/.../EventTimerTests.swift`

**Interfaces:**
- Produces:
  - `enum CountdownPhase: Equatable { case idle, countdown(TimeInterval), warning(TimeInterval), pulsing(TimeInterval), started }` with `static func phase(start: Date, now: Date) -> CountdownPhase`. The thresholds are: `>= 600` → idle; `(300, 600)` → countdown; `(60, 300]` → warning (red); `(0, 60)` → pulsing; `<= 0` → started.
  - `@Observable @MainActor final class EventStore { var today: [CalendarEvent] { get }; func replace(_ events: [CalendarEvent]); func dismiss(_ id: String); func tick(now: Date) -> [String] }`. `today` excludes dismissed, ended and all-day events, sorted by start. `tick` returns the IDs whose tone should play now, and each ID is returned at most once per start time (tracked as `"\(id)@\(start)"`, so a rescheduled meeting plays again).

- [ ] **Step 1:** Write tests: the boundary values `599 s → countdown`, `600 → idle`, `300 → warning`, `59 → pulsing`, `0 → started`; `nextEventFirst`; `endedEventsHidden`; `dismissRemoves`; `toneFiresOnceAcrossRefreshes` (Review Focus 3: tick past the start, `replace` with the same event, tick again → just one ID); `rescheduledEventFiresAgain`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement it.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: event store and countdown phases`.

### Task 7: OAuth, Keychain and GraphClient

**Files:** Create `Graph/OAuth.swift`, `Graph/Keychain.swift`, `Graph/GraphClient.swift` and `Tests/.../GraphClientTests.swift`

**Interfaces:**
- Produces:
  - `protocol HTTPTransport: Sendable { func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) }` (with a `URLSession` conformance).
  - `protocol TokenProvider: Sendable { func accessToken(forceRefresh: Bool) async throws -> String }`
  - `actor OAuth: TokenProvider { init(clientID: String, tenantID: String, transport: HTTPTransport); func signIn() async throws; func signOut() }`. Scopes: `offline_access User.Read Mail.Read Calendars.Read Chat.Read`. Endpoints: `https://login.microsoftonline.com/{tenant}/oauth2/v2.0/authorize|token`. Redirect: `myassistant://auth`, using `ASWebAuthenticationSession(callbackURLScheme: "myassistant")`. The refresh token goes in the Keychain under service `de.sebastiangross.MyAssistant`, account `refresh_token`.
  - `enum GraphError: Error { case unauthorized, throttled(retryAfter: TimeInterval), http(Int), consentRequired }`
  - `struct GraphClient: Sendable { init(tokens: TokenProvider, transport: HTTPTransport); func get<T: Decodable>(_ urlOrPath: String, as: T.Type) async throws -> T; func delta<T: Decodable>(start: String, deltaLink: URL?) async throws -> (items: [T], deltaLink: URL) }`. `delta` follows `@odata.nextLink` until it reaches `@odata.deltaLink`. If it gets a 410, it restarts from `start`.

- [ ] **Step 1:** Write tests with a `MockTransport` and a `MockTokens`: `pkceChallengeIsS256OfVerifier` (RFC 7636 vector: verifier `dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk` → `E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM`), `deltaFollowsNextLinksAndReturnsDeltaLink`, `unauthorizedTriggersRefreshThenSurfacesError` (Review Focus 4: a 401 → retry once with `forceRefresh: true` → a second 401 throws `.unauthorized`), `throttledParsesRetryAfter`, `forbiddenMapsToConsentRequired` (403).
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement it with CryptoKit `SHA256` and base64url encoding.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: graph oauth and client`.

### Task 8: Sources and the poller

**Files:** Create `Sources/*.swift` and `Tests/.../SourcesTests.swift`, with JSON fixtures in `Tests/MyAssistantTests/Fixtures/`.

**Interfaces:**
- Consumes: `GraphClient`, `AssistantNotification`, `CalendarEvent`.
- Produces:
  - `enum SourceStatus: Equatable { case disabled, signedOut, ok(Date), error(String), consentRequired }`
  - `protocol NotificationSource { var kind: SourceKind { get }; func fetchNew(deltaLink: URL?) async throws -> (items: [AssistantNotification], deltaLink: URL?) }`. `MailSource` returns only messages that are `isRead == false` and not `@removed`. On its first run (no delta link) it returns only items from the last 24 h. `TeamsSource` compares `lastMessagePreview.id` for each chat against a new `PersistedState.teamsLastSeen: [String: String]` field (chat ID → message ID), skips messages from me (`/me` id) and skips everything on the first run.
  - `struct CalendarSource { func fetchToday(now: Date) async throws -> [CalendarEvent] }`, which uses `calendarView` for the local day with `$select=subject,start,end,location,organizer,webLink,onlineMeeting,isAllDay,isCancelled` and the header `Prefer: outlook.timezone="UTC"`. Cancelled events are dropped.
  - `@MainActor final class Poller { init(model: AppModel); func start(); func stop(); func refreshNow() }`. It uses one `Task` per source with the intervals 30/20/60 s. On `.throttled`, it sleeps for `retryAfter`. On other errors it uses exponential backoff capped at 5 min and sets the status. Existing items are always kept. It wakes up on `NSWorkspace.didWakeNotification`.

- [ ] **Step 1:** Write fixture-based tests: `mailMapsSenderSubjectPreviewWebLink`, `mailFirstRunSkipsOlderThan24h`, `teamsEmitsOnlyChangedChatsNotFromMe`, `teamsFirstRunEmitsNothing`, `calendarParsesUTCAndJoinURL`, `calendarDropsCancelled`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement it. Mail title: subject. Sender: `from.emailAddress.name`. Preview: `bodyPreview` (keep up to 3 lines, and limit the card to 4 lines in the UI).
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `feat: mail, teams, calendar sources and poller`.

### Task 9: UI with Liquid Glass

**Files:** Create `UI/RootView.swift`, `UI/NotificationCard.swift`, `UI/SnoozeSheet.swift`, `UI/EventCard.swift`, `System/Opener.swift` and `App/AppModel.swift`.

**Interfaces:**
- Consumes: all the stores, `CountdownPhase`, `SnoozeOption`, `DockController`.
- Produces: `@Observable @MainActor final class AppModel { let notifications: NotificationStore; let events: EventStore; var status: [SourceKind: SourceStatus]; var settings: AppSettings; func open(_ url: URL?) }`, plus a 1 s `Timer` that calls `notifications.tick()` and `events.tick(now:)` and plays `Resources/chime.aiff` through `NSSound` for each returned ID (if `playTone` is on).

- [ ] **Step 1:** `RootView`: a `GlassEffectContainer` with a grip bar (the drag handle) and a `VStack` of two equal halves, each with a section header ("Messages" with a count badge, and "Today" with the date). Each header shows a status dot per source (green ok, orange error with a tooltip, gray signed out). Each half is a `ScrollView` with a `LazyVStack(spacing: 8)`. The window background is `.glassEffect(.regular, in: .rect(cornerRadius: 20))`, inset by 8 pt from the screen edge. Empty states use `ContentUnavailableView`.
- [ ] **Step 2:** `NotificationCard`: a 4 pt leading color bar in `kind.color`, a light tint of that color on the glass (`.glassEffect(.regular.tint(kind.color.opacity(0.25)))`), a source icon (`message.fill`/`envelope.fill`), the sender in bold, the title, a preview with `lineLimit(4)` and the relative time. The trailing buttons are `clock.arrow.circlepath` (opens `SnoozeSheet` as a `.popover`) and `checkmark.circle` (`markDone`). Tapping the body calls `open(openURL)` and does nothing else. New items appear with `.transition(.move(edge: .top).combined(with: .opacity))`.
- [ ] **Step 3:** `SnoozeSheet`: buttons for the five fixed options and "Custom…", which shows a `DatePicker(.graphical)` with its default set to tomorrow at the original time, and a "Snooze" confirm button.
- [ ] **Step 4:** `EventCard`: the time range, subject, location and organizer. The trailing buttons are "Join" (`video.fill`, only when `joinURL != nil`) and dismiss (`xmark.circle`). Phase styling: `countdown` shows a monospaced `mm:ss` badge; `warning` adds a red tint and red badge; `pulsing` adds `.phaseAnimator([1.0, 0.55])` on the opacity and scale of the tint, with a 0.6 s repeat; `started` shows the red tint, no animation and the badge "now". Tapping the body opens `webLink`. The view refreshes through `TimelineView(.periodic(from: .now, by: 1))`.
- [ ] **Step 5:** Check by hand with a `#Preview` and a debug menu item "Inject sample data" (DEBUG builds only) that adds 3 notifications and events at +12, +4, +0.5 and −0.1 min. Confirm the newest card is on top, the colors, that clicking a card doesn't remove it, that done and snooze remove it, and that the event shows red, then pulses, then stays red with the tone playing once.
- [ ] **Step 6:** Commit: `feat: glass UI for notifications and calendar`.

### Task 10: Settings and launch at login

**Files:** Create `UI/SettingsView.swift`, `System/LaunchAtLogin.swift` and `Tests/.../SettingsTests.swift`

**Interfaces:**
- Consumes: `AppSettings`, `OAuth`, `Poller`, `ScreenReserver`, `DockController`.
- Produces: `enum LaunchAtLogin { static var isEnabled: Bool; static func set(_ on: Bool) throws }`, which wraps `SMAppService.mainApp.register()`/`unregister()`.

- [ ] **Step 1:** Write `SettingsTests.settingsDecodeWithMissingKeys`. Old state files must decode, so add `init(from:)` with defaults for any missing keys.
- [ ] **Step 2:** Run the test. Expected: FAIL. Then implement the decoding and run it again. Expected: PASS.
- [ ] **Step 3:** `SettingsView` is a `TabView`:
  - **Accounts:** Client ID and Tenant ID fields, a short how-to (an Entra app registration, as a public client, with redirect `myassistant://auth`, delegated permissions `Mail.Read`, `Calendars.Read`, `Chat.Read` and `offline_access`), Sign in and Sign out buttons, and the signed-in UPN.
  - **Sources:** a toggle for each `SourceKind`, with its status and a "Refresh now" button.
  - **General:** a toggle for "Launch at login" (shows the error inline if registering fails), a "Dock edge" picker, a "Reserve screen space (requires Accessibility)" toggle with a button that opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`, and a "Play tone at meeting start" toggle.
- [ ] **Step 4:** Check by hand with the bundled app: sign in with a real tenant and confirm that mail, chats and today's events appear within one poll interval. Turn launch at login on, log out and back in, and confirm the app starts docked at the saved place.
- [ ] **Step 5:** Run `swift test` (everything passes). Commit: `feat: settings, sign-in and launch at login`.
