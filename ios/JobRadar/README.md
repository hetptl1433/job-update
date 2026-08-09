# Orbit for iPhone

Orbit is a personal AI command center — email, jobs, health, tasks and an AI
assistant organized around what needs your attention. Native SwiftUI.

The project lives on the `agent/ios-job-radar` branch so the existing Vercel
website remains untouched. The internal Xcode target and bundle identifier are
kept as `JobRadar` / `com.hetpatel.jobradar` for signing and backend stability;
the user-facing name is **Orbit**.

## Architecture

```
Views          → SwiftUI screens (Home, Inbox, Jobs, Health, Automations, Assistant, Settings)
State          → AppState (single source of session/routing truth)
Authentication → AuthenticationManager, GoogleAuthService (GoogleSignIn), UserSession, Keychain
Repositories   → JobRepository, GmailRepository, HealthRepository
Services       → AssistantService (AI via backend), AutomationService, NotificationManager
Networking     → APIClient (talks only to our backend — never OpenAI directly)
Models         → JobApplication (SwiftData) + domain models
Design         → AppTheme (centralized black/white/gray tokens, light + dark)
Config         → AppConfig (app name, apiBaseURL, GIDClientID)
```

The data flow is: **your services → our backend → OpenAI → one clean dashboard.**
The iOS app holds no OpenAI key.

## Generate and open the Xcode project

```bash
brew install xcodegen
cd ios/JobRadar
xcodegen generate
open JobRadar.xcodeproj
```

`project.yml` is the source of truth. Re-run `xcodegen generate` after adding
files, packages, or Info.plist keys.

## Required manual configuration

### 1. Google Cloud (Sign in with Google + Gmail/Calendar)

1. In the [Google Cloud Console](https://console.cloud.google.com/), create a
   project and configure the OAuth consent screen (External).
2. Create an **iOS OAuth client ID** for bundle id `com.hetpatel.jobradar`.
3. Add the client ID to `project.yml` (`info.properties`) or
   `JobRadar/Resources/Info.plist` as `GIDClientID`, then `xcodegen generate`.
4. Add a URL scheme equal to your **reversed client ID**
   (`com.googleusercontent.apps.XXXX`) under `CFBundleURLTypes`.
5. Add the read-only scopes to the consent screen:
   `https://www.googleapis.com/auth/gmail.readonly`,
   `https://www.googleapis.com/auth/calendar.readonly`.

Until `GIDClientID` is set, sign-in returns a clear "not configured" message
(the app still builds and runs). If the GoogleSignIn package is unavailable, the
auth layer falls back to a simulated provider so the full flow stays testable.

### 2. Backend (AI + Gmail classification)

The app calls our backend at `APIBaseURL` (default
`https://job-update.vercel.app`). Implement these endpoints server-side, holding
the OpenAI key on the server and using the OpenAI Responses API:

- `POST /api/assistant/ask` — `{ prompt, tools[] }` → `{ text, actions[] }`
- `POST /api/assistant/summarize` / `classify` — `{ text }` → `{ text }`
- `POST /api/assistant/daily-brief` → `{ text }`
- `GET  /api/mobile/gmail/important` and `search?q=` → `{ messages[] }`
- (existing) `GET/PUT /api/tracker`, `POST /api/mobile/push/register`

## Capabilities

Confirm in Xcode: Background Modes (Background fetch, Remote notifications) and
Push Notifications. Sign in with Apple was removed — Google is the identity
provider now.

## Data honesty

Live screens show real data or explicit empty/disconnected states — never fake
data. Mock data lives in `Mocks/` and is used only in SwiftUI previews.

## Vercel environment variables (server-side only)

`OPENAI_API_KEY`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `OAUTH_STATE_SECRET`,
`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`,
`APNS_ENVIRONMENT`. Never commit provider secrets or Apple `.p8` keys, and never
ship `OPENAI_API_KEY` in the iOS app.
