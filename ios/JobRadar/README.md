# Orbit for iPhone

Orbit is a native SwiftUI command center for provider-neutral email, calendars,
tasks, and job tracking. It combines Gmail and Microsoft 365 mail, Apple/Google/
Outlook calendars, uses OpenAI Structured Outputs to extract updates, and lets
the user approve every important tracker change.

The internal target and bundle identifier remain `JobRadar` and
`com.hetpatel.jobradar`; the user-facing product name is **Orbit**.

## Working flow

1. The first Google sign-in is the single **primary Orbit identity**. Email
   Settings can then add multiple independently authorized Gmail and Outlook/
   Microsoft 365 inboxes; adding one never changes the primary profile.
2. **Connect OpenAI processing** validates a user-provided OpenAI API key and
   stores it in the iOS Keychain for this personal-development build.
3. **Scan email** finds up to 40 likely job messages from the last 60 days in
   every connected mailbox. Each detected update retains its source mailbox,
   sender, subject, date, status, reason, and next action.
4. The OpenAI Responses API returns a strict, schema-constrained important inbox
   and proposed job updates. Raw email is not written to local storage.
5. The user reviews proposed updates one at a time with compact **Update** and
   **Ignore** actions. Accepted jobs are stored with SwiftData and are not
   deleted if the optional backend is down.

The app never sends email or silently changes the job tracker.

## Generate and build

```bash
brew install xcodegen
cd ios/JobRadar
xcodegen generate
xcodebuild \
  -project JobRadar.xcodeproj \
  -scheme JobRadar \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

`project.yml` is the source of truth. Run `xcodegen generate` after changing
packages, build settings, assets, entitlements, or Info.plist properties.

## Google Cloud setup

1. Enable both the **Gmail API** and **Google Calendar API** in the Google Cloud project.
2. Configure the OAuth consent screen and add the read-only scopes:
   `https://www.googleapis.com/auth/gmail.readonly`.
   `https://www.googleapis.com/auth/calendar.readonly`.
3. Create an iOS OAuth client for bundle ID `com.hetpatel.jobradar`.
4. Put its client ID in `GIDClientID` in `project.yml`.
5. Put the reversed client ID in `CFBundleURLTypes` in `project.yml`.
6. If the OAuth app is still in Testing, add the Google account as a test user.

The repository currently contains a configured iOS client ID, but the Gmail API,
consent screen, enabled APIs, and test-user state still have to be correct in Google Cloud.

## Microsoft Entra / Outlook setup

Outlook support is implemented but deliberately has no fake client ID. Before
the Connect Outlook button can authenticate:

1. In Microsoft Entra, create an app registration that supports the account
   audience you want. `common` in `MicrosoftTenantID` permits personal Microsoft
   accounts and organizational tenants when the registration allows them.
2. Add the iOS/macOS platform using bundle ID `com.hetpatel.jobradar` and redirect
   URI `msauth.com.hetpatel.jobradar://auth`.
3. Enable public client flows and add delegated Microsoft Graph permissions
   `User.Read`, `Mail.Read`, and `Calendars.Read`.
4. Put the Application (client) ID in `MicrosoftClientID` in `project.yml`, run
   `xcodegen generate`, and rebuild.
5. If the tenant requires admin consent, grant it before testing. Orbit requests
   read access only; it does not send Microsoft email or modify calendar events.

## Apple Calendar and Apple Health connection process

- In Orbit, open **Home → profile → Settings → Connected Services**. Connect any
  combination of Google Calendar, Apple Calendar, and Outlook Calendar. All are
  normalized into one 14-day timeline. Apple Calendar displays the native iOS
  permission sheet. Untimed Orbit To Dos remain local; timed To Dos and Orbit
  Reminders create linked Apple Calendar events, and edits to those events sync
  back into Orbit. Any Apple, Google, or Outlook event can be explicitly added
  to To Do, but events are never converted automatically. Google and Outlook
  remain read-only OAuth sources.
- **Apple Health** is device-local. On a physical iPhone, tap Connect Apple
  Health and approve any combination of steps, sleep, active energy, heart rate,
  and workouts. Orbit requests read access only and does not write Health data.
- Health permissions can later be changed in iOS **Settings → Privacy &
  Security → Health → Orbit**.
- Calendar permissions can be changed in iOS **Settings → Privacy & Security →
  Calendars → Orbit**.

## Tasks and widget

Orbit Tasks is the source of truth for manual, email, job, AI, calendar-linked,
and automation tasks. The app and `OrbitTasksWidget` extension share real Codable
task data through App Group `group.com.hetpatel.jobradar`. The small, medium, and
large To Do widgets prioritize overdue, today, high-priority, AI/email, then
upcoming items. A separate Reminders widget shows upcoming reminders. App Intents
allow completion from either widget, plus buttons open the matching editor, and
Siri/Shortcuts can create To Dos or timed reminders directly in Orbit.

## Finance and Plaid

Finance is a primary tab for balances, credit-card debt, monthly inflow/outflow,
accounts, recent transactions, and multiple connected institutions. The Home
screen also shows a compact Finance summary after the first account is linked.
Health remains available from its Home card and Settings.

Plaid Hosted Link runs in an `ASWebAuthenticationSession` and returns through
Orbit's `orbit://finance` URL scheme. This keeps the real bank sign-in in an
Apple-protected browser while allowing a Personal Team development build with
no Associated Domains entitlement. `FinanceAPIBaseURL` points to the server
contract documented in `Backend/README.md`; the Plaid client ID, secret,
public/access tokens, sync cursors, and raw provider responses remain on that
server. Orbit stores only a random pending connection ID, checks the signed
Plaid webhook result, and then reloads normalized Finance data. Until the server
is deployed, Finance shows **Finance server required** instead of a simulated
bank connection.

For a signed physical-device build, create the App Group in the Apple Developer
portal and add it to both App IDs (`com.hetpatel.jobradar` and
`com.hetpatel.jobradar.tasks-widget`). Xcode project entitlements are already set.

## OpenAI setup and production security

For a personal development run, create an API key at `platform.openai.com`, then
connect it during onboarding or in Settings. OpenAI API billing is separate from
ChatGPT Plus. The model defaults to `gpt-4o-mini` and can be changed with the
`OpenAIModel` Info.plist value.

Do **not** distribute a build that asks users to put an OpenAI key on the phone.
Before TestFlight/App Store distribution, add a backend endpoint that holds
`OPENAI_API_KEY` server-side and replace the `OpenAIClient` implementation with a
backend-backed assistant/email-analysis service. Mobile applications cannot
guarantee that an embedded or locally entered provider secret is safe.

## Architecture

```text
Views          SwiftUI screens and review UI
State          AppState: primary identity, provider connections, email → AI pipeline
Authentication GoogleSignIn + MSAL + Keychain-backed tokens
Networking     Gmail/Graph mail, Apple/Google/Graph calendar, OpenAI client
Services       Structured email intelligence, assistant, reminders/notifications
Repositories   SwiftData jobs, unified inbox/calendar, App Group tasks, HealthKit
Design         Premium black/white/neutral UI with restrained semantic color
Assets         Minimal black-and-white 1024px app icon in Assets.xcassets
```

The tracker runs in local-only mode by default (`APIBaseURL` is empty). Set that
key only after deploying compatible `/api/tracker` and push routes. Finance uses
the separate `FinanceAPIBaseURL`, so a working bank server never causes false
job-sync errors. Local/manual/email-derived jobs remain available when the
optional tracker backend is unavailable.
