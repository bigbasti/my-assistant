# My Assistant

A docked, always-on-top macOS panel showing Teams chats, Outlook mail and today's meetings. Everything is read locally on your Mac; there is no sign-in and no cloud access.

## Build and run

    ./scripts/bundle.sh          # builds build/My Assistant.app (ad-hoc signed)
    open "build/My Assistant.app"

Copy the app to `/Applications` before enabling **Launch at login**; registering a login item usually fails for apps run from elsewhere.

## Tests

    swift run MyAssistantTests [--filter Name]

(`swift test` runs nothing with Command Line Tools only.)

## Setup

1. **Full Disk Access** (Teams and Outlook alerts): System Settings → Privacy & Security → Full Disk Access, add `My Assistant.app`. Settings → Sources has a button that opens this pane.
2. **Calendar access** (meetings): allow the prompt, or enable it in Privacy & Security → Calendars. Settings → Sources has a button for this too.
3. **Notifications**: turn on notifications for Teams and Outlook in System Settings → Notifications. Banners may be set to None; alerts still arrive.
4. **Exchange account**: add your work account in System Settings → Internet Accounts with Calendars enabled, so meetings appear in Calendar.

Teams and Outlook alerts are read from the macOS notification database; meetings are read through EventKit.

## Accessibility

"Reserve screen space" moves other apps' windows out of the dock strip. Grant My Assistant access in System Settings → Privacy & Security → Accessibility.

## Rebuild note

`scripts/bundle.sh` signs the app with your first "Apple Development" certificate, so macOS keeps the Accessibility, Full Disk Access, Calendar and Mail automation permissions across rebuilds. Without such a certificate (or with `SIGN_IDENTITY=-`) the app is signed ad hoc; every rebuild then changes its code identity and those permissions must be granted again.
