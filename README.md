# My Assistant

A docked, always-on-top macOS panel showing Teams chats, Outlook mail and today's calendar from Microsoft Graph.

## Build and run

    ./scripts/bundle.sh          # builds build/My Assistant.app (ad-hoc signed)
    open "build/My Assistant.app"

Copy the app to `/Applications` before enabling **Launch at login**; registering a login item usually fails for apps run from elsewhere.

## Tests

    swift run MyAssistantTests [--filter Name]

(`swift test` runs nothing with Command Line Tools only.)

## Entra app setup

Register an app in Microsoft Entra ID:

- Platform: public client (mobile/desktop), redirect URI `myassistant://auth`
- Delegated permissions: `Mail.Read Calendars.Read Chat.Read offline_access User.Read`
- Enter the Client ID and Tenant ID in Settings → Accounts, then Sign in.

`Chat.Read` may need admin consent in corporate tenants; the Teams source then shows "consent required" while the others keep working.

## Accessibility

"Reserve screen space" moves other apps' windows out of the dock strip. Grant My Assistant access in System Settings → Privacy & Security → Accessibility.
