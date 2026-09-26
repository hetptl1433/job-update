# Orbit for iPhone and iPad

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
3. **Scan email** analyzes a bounded batch of up to 40 unseen likely job
   messages per connected mailbox. Gmail and Outlook pages are drained across
   later scans without advancing past a remaining backlog. A protected,
   owner-scoped ledger stores provider IDs/cursors and accepted or dismissed
   decisions—not raw email—so unchanged messages are not repeatedly sent to AI.
   Each detected update retains its source mailbox, sender, subject, date,
   status, reason, and next action.
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
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO build
```

`project.yml` is the source of truth. Run `xcodegen generate` after changing
packages, build settings, assets, entitlements, or Info.plist properties.

Orbit is a universal app. On an iPad in a regular-width window, a sidebar
replaces the iPhone dock and screens keep a readable column width. Slide Over
and narrow Split View windows use the iPhone layout. CarPlay settings are
hidden on iPad, and the watch app pairs only with iPhone.

The first time you build in Xcode, it asks you to trust mlx-swift's `CudaBuild`
package plugin; choose **Trust & Enable**. The plugin does nothing on Apple
platforms. Command-line builds pass `-skipPackagePluginValidation` instead.

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

## CarPlay

Orbit includes a CarPlay screen-mirroring pipeline modeled on the public design
used by video-in-car apps:

1. The user explicitly starts **Orbit Screen Broadcast** from Orbit Settings.
   Apple's ReplayKit consent sheet is always shown; capture cannot start
   silently.
2. The embedded broadcast extension captures the iPhone display and app audio,
   encodes them as a rolling fragmented-MP4 HLS stream, and stores only the
   latest segments in the shared App Group cache.
3. The main app serves that stream over a private local HTTP listener advertised
   on the active CarPlay link and plays it with `AVPlayer`.
4. The CarPlay list item requests `.video` presentation with
   `CPPlaybackConfiguration`, allowing CarPlay to put the live stream on a
   compatible vehicle display. External playback uses aspect fill, so it adapts
   to each car display without distortion. A portrait iPhone screen is cropped
   vertically on a wide car display.

For full-screen video without a portrait phone frame, Settings → CarPlay Videos
can import an MP4, M4V, or MOV file from Files or save a direct HTTPS HLS/MP4
link. Local HTTP links on the user's network are also accepted. Open **Orbit
Video** on CarPlay and choose a saved video; it plays the original source with
`AVPlayer` instead of a ReplayKit screen capture. Imported files are copied to
Application Support so the Files provider need not stay open. Aspect fill may
crop the edges of videos whose shape differs from the car display. Webpage links
and protected videos from other apps are not direct media sources.

Protected/DRM video can appear black. CarPlay and the vehicle decide when video
is available and can switch to audio-only when it becomes unavailable. This is
for passengers while parked.

To activate the included CarPlay scene for development and distribution:

1. Request the **Video app** CarPlay entitlement from the
   [Apple CarPlay developer page](https://developer.apple.com/carplay/).
2. After Apple grants the capability to `com.hetpatel.jobradar`, add
   `com.apple.developer.carplay-video: true` under the main
   target's `entitlements.properties` in `project.yml`.
3. Confirm that App Group `group.com.hetpatel.jobradar` is enabled for both
   `com.hetpatel.jobradar` and
   `com.hetpatel.jobradar.screen-broadcast` in the Developer portal.
4. Regenerate the project, refresh both provisioning profiles, and test with the
   video-capable CarPlay Simulator plus a real compatible vehicle. The simulator
   will not show Orbit without the approved video entitlement.

The entitlement is intentionally absent from the checked-in signing file until
Apple grants it; restricted entitlements that are not in the provisioning
profile prevent physical-device installation.

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

## On-device Orbit Chat

Typed Orbit Chat runs on the iPhone or iPad by default. Orbit uses
[MLX](https://github.com/ml-explore/mlx-swift) to run an open-weights model on
the GPU, so questions, the Orbit data snapshot, and replies never leave the
device, and chat works offline. Typed chat needs no OpenAI key; live voice,
CarPlay, and email scanning still use OpenAI. Settings → Orbit Chat switches
typed chat to OpenAI.

- **Models:** Settings lists only the models the device has memory for and
  marks the largest one it runs comfortably as Recommended:
  - Qwen3 0.6B (about 350 MB) for faster, simpler answers.
  - Qwen3 1.7B (about 1 GB), recommended on 6 GB iPhones.
  - Qwen3 4B Instruct 2507 (about 2.3 GB), recommended on 8 GB iPads and
    iPhones. 6 GB iPhones offer it when iOS lets Orbit use at least about
    3.8 GB, but it answers slowly there.
  - Qwen3 8B (about 4.6 GB), offered when iOS lets Orbit use at least about
    6.1 GB. That depends on the device's per-app limit, not just its RAM, so
    an 8 GB iPad may or may not offer it. It is recommended on 16 GB iPads.

  All are 4-bit and pinned to exact Hugging Face commits in
  `LocalModelOption`, so the weights, tokenizer, and chat template cannot
  change underneath the app. Orbit has the `increased-memory-limit`
  entitlement, and Settings shows how much memory the device gives Orbit.
  Apple's built-in Foundation Models require Apple Intelligence (iPhone 15 Pro
  or newer), so Orbit brings its own model.
- **First use:** Orbit Chat and Settings offer a one-time download from Hugging
  Face. Use Wi-Fi and keep Orbit open until it finishes. The files live in
  Application Support, are excluded from backups, and can be deleted in
  Settings, either all at once or every model except the selected one.
- **Prompt budget:** a small local model cannot take the full cloud prompt.
  `LocalAssistantPrompt` keeps the same privacy rules in a shorter form and fits
  Orbit data into the model's prompt budget: 2,400 tokens for the small models,
  3,600 for 4B and 3,200 for 8B. Every list stays represented, lists the
  question is about get more room, and a trimmed list says how many items were
  left out.
- **Physical device only:** MLX needs Metal GPU features the iOS Simulator does
  not provide, so the simulator shows an "isn't available" state.
- **Memory and background:** the model loads when chat opens and unloads when
  chat closes or Orbit moves to the background. iOS does not allow GPU work from
  background apps, so a reply stops if Orbit leaves the screen.

Console.app shows load time and tokens per second under subsystem
`com.hetpatel.jobradar`, category `LocalModel`.

## OpenAI setup and production security

For a personal development run, create an API key at `platform.openai.com`, then
connect it during onboarding or in Settings. OpenAI API billing is separate from
ChatGPT Plus. The text/email model defaults to `gpt-4o-mini`; Settings offers a
curated quality/cost selector while `OpenAIModel` remains the bundled fallback.

Orbit Chat's **Live conversation** uses the OpenAI Realtime API with
`gpt-realtime` by default (`OpenAIRealtimeModel` is the bundled fallback, and
Settings offers compatible Realtime choices). It streams
24 kHz microphone audio and native model speech over one continuous session,
shows transcript bubbles as turns complete, and seeds a new session with the
protected on-device conversation plus the current privacy-filtered Orbit data
snapshot. Finance details are included only when the user has enabled Finance
sharing for the assistant.

**Personal Memory** is context, not model training. Explicit typed commands such
as `Remember that I prefer concise answers` save a bounded owner-scoped memory
on the iPhone. An optional setting can locally detect direct stable statements
and queue them for approval; pending suggestions are never sent to the model.
Approved memories can be reviewed, deleted, or disabled. Common secret patterns
are rejected, and relevant approved memories are separated from instructions as
untrusted reference data. Live voice is read-only for Personal Memory; saving or
deleting memory requires typed Chat or Settings.

Do **not** distribute a build that asks users to put an OpenAI key on the phone.
Before TestFlight/App Store distribution, add a backend endpoint that holds
`OPENAI_API_KEY` server-side, mint short-lived Realtime client credentials, and
move the mobile live transport to WebRTC. Also replace `OpenAIClient` with a
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
