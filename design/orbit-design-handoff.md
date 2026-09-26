# Orbit design handoff

Use [orbit-refined.html](orbit-refined.html) as the visual reference for a native SwiftUI refinement of the current Orbit app. Open it directly in a browser; the reference needs no build, account connection, or remote assets.

The HTML is a design prototype with static sample data and illustrative state transitions. Its balances, messages, tasks, charts, assistant replies, connection indicators, and automation states do not represent live results. Existing iOS models, repositories, services, consent, and navigation remain authoritative. This guide describes intended design coverage; it does not certify interaction testing or native feature completeness.

## Design direction

- Keep the existing black canvas and signal red identity. This is a refinement of Orbit, with the same primary destinations and tools.
- Make the next task the clearest action on Home. Give financial and health detail room on their own screens.
- Improve hierarchy through larger page titles, tabular numbers, calmer metadata, and consistent row spacing.
- Use compact grouped sections, thin dividers, and fewer competing card outlines. A subtle warm tint distinguishes the primary To Do surface.
- Reserve glow for the Orbit launcher and a few primary brand moments. Keep ordinary content crisp and readable.
- Reuse the existing logo and native SF Symbols where possible; the inline HTML icons are visual approximations.

## Palette and layout

| Token | Value | Use |
| --- | --- | --- |
| Background | `#070708` | Persistent black canvas |
| Primary surface | `#111114` | Cards and dock |
| Secondary surface | `#1A1A1F` | Inputs and grouped controls |
| Elevated surface | `#222228` | Raised elements |
| Primary / secondary / tertiary text | `#F8F8FA` / `#B2B2BC` / `#7E7E89` | Reading hierarchy |
| Border / separator | `#303037` / `#242429` | Outlines and dividers |
| Brand / coral | `#F3263E` / `#FF6675` | Primary actions and selected accents |
| Brand gradient | `#FF354B` to `#D4142C` | Orbit launcher and selected primary actions |
| Success / warning | `#55D98B` / `#FFC15C` | Meaningful status |
| Info / purple | `#6DAEFF` / `#C69BFF` | Contextual status and health categories |
| Destructive | `#FF5264` | Existing native destructive token |

The desktop showcase has a 402 px outer phone, including two 6 px borders: its content reference width is **390 pt**. Treat CSS pixels inside that reference as starting layout measurements, then translate to native points and scalable type.

- Base horizontal content inset: 21 pt. The mobile HTML uses about 22 px and reduces to 16 px on very narrow screens.
- Preserve the native spacing scale of 4, 8, 12, 16, 24, and 32 pt; apply the reference's small optical adjustments thoughtfully.
- Existing corner radii are 10, 14, and 20 pt. The reference uses about 22 px for prominent cards and smaller radii for controls.
- Use the system font. Page titles are roughly 27–31 pt; large financial values are about 42 pt. Map compact browser metadata to readable Dynamic Type styles rather than freezing every small pixel value.
- White text on small filled buttons uses the existing deeper gradient endpoint `#D4142C` for contrast; the signal red `#F3263E` remains the brand and selection color.
- Native controls need at least 44 × 44 pt hit areas, including small-looking checkboxes and icons. Expand invisible hit regions without changing their visual size.
- Respect safe areas, the keyboard, reduced motion, contrast, VoiceOver labels, and large text. Allow cards and rows to grow; avoid fixed phone-height assumptions.
- Keep a persistent bottom dock with a separately scrollable content region. Native safe-area insets replace the mock status bar, Dynamic Island, phone frame, and home indicator.
- The desktop title, screen navigation, design notes, palette, footer, and preview labels are presentation scaffolding. Do not ship them in the iOS app.

## Navigation contract

The dock order stays **Home · Finance · Orbit · Health · More**.

- Home, Finance, Health, and More are primary destinations.
- Orbit is a persistent launcher: tap opens the chat sheet; hold for at least 0.45 seconds opens full-screen live voice. Expose a separate accessible voice action. A hold must not also trigger chat.
- More tap opens the hub. Holding More reveals shortcuts for To Do, Jobs, Inbox, Automations, and Settings.
- To Do, Jobs, and Inbox remain secondary destinations under the selected More dock item. Preserve their distinct `AppState.Tab` values for shortcuts and deep links.
- Automations and Settings open sheets. The Home profile button also opens Settings.
- Preserve existing Back/Done behavior, selected state, restored conversation, task deep links, and quick capture entry points.

## Feature map to retain

| Surface | Required native behavior |
| --- | --- |
| Home | Task-first heading, greeting, open/due count, add, complete/edit, suggested email actions, and See all. Supporting context includes attention, upcoming calendar, jobs, inbox, email scan, finance, health, and Ask Orbit. Compact visual regrouping must keep these destinations accessible. |
| To Do | Quick capture, search, Overdue/Today/Upcoming/Anytime groups, suggestions with accept/dismiss, collapsible Completed, and completion/deletion Undo. Editor retains notes, optional date/time, alert, priority, and source. |
| Calendar | Upcoming event time, title, location/provider, and Add to To Do with an already-added state. Keep the full timeline reachable. Dated tasks link to Apple Calendar; undated tasks remain in the list. |
| Jobs | Summary metrics for Active, Interview, Offers, Waiting, Follow-up, and Rejected; attention; recent active applications; company/role search; add/edit; and email scan. Preserve pipeline, priority, next action, follow-up date, recruiter, and detail fields. |
| Detected job changes | Show the proposed company/role/status, reason, next action, and email source. Require Update or Ignore; do not silently modify the tracker. |
| Inbox | All Accounts/Gmail/Outlook filters; Needs Action/Important/Jobs/Everything Else sections; sender, time, subject, AI summary, provider/mailbox, and action status. Keep refresh and saved/offline states. |
| Finance | Total position, cash, card debt, investments, inflow/outflow, spending period/category exploration, accounts, transactions, recurring payments, income, institution management, and refresh. Keep selected period, currency, and transaction semantics. |
| Income | Confirmed posted income and unresolved deposits, classification corrections, recurring income sources, history, expected pay, goals, and the income calculator. Keep transfers/refunds separate and gross estimates distinct from observed net deposits. |
| Recurring / transactions | Keep confirmed versus possible recurring charges, review decisions, account/category filters, transaction details, and merchant corrections. Prototype transitions must map to existing native operations. |
| Health | Apple Health source and refresh, period selection, overall trend, body load factors/baseline, activity, vitals, sleep, workouts, mobility, body, mindfulness, metric detail, and sources/privacy. Compact cards must retain routes to deeper categories. |
| More | Workspace cards for To Do, Jobs, Inbox, and Automations; a clear account/settings destination. |
| Chat | Suggested prompts, compose/send, conversation, live voice entry, new conversation, Personal Memory, and existing explicit task/memory commands. Preserve approved memory and pending Remember/Not now decisions. |
| Live voice | Full-screen orb and connection/listening/thinking/speaking/muted/error states; live captions, Mute/Unmute, Captions, End, Retry when appropriate, and model selection. Chat and voice share their persisted thread. |
| Settings | Account, multiple Gmail/Outlook mailboxes, banks/cards, calendars, Apple Health, AI connection/model settings, context consent, Personal Memory, notifications, appearance, Siri/widgets, privacy, and sign-out/disconnect. |
| Automations | Important Email Watch, Job Follow-up, Morning Brief, Interview Reminder, and Weekly Health Summary, each with frequency and enable state. |

The prototype intentionally simplifies transaction search/range/type filters, the multi-source income calculator (hourly, salary, monthly, one-time, bonus, optional take-home), and annual income goals. Preserve all of those existing native capabilities when implementing.

Job filter chips and compact detail arrangements in the reference express browsing intent. Reconcile them with the native model and existing latest-five active presentation; do not lose closed applications from totals or remove fields to fit a mock screen.

## State and privacy rules

- Implement loading, empty, disconnected, unavailable, error/retry, syncing, and cached-data states where each native repository supports them. Do not fill absent account data with the prototype's samples.
- Email scanning is read-only. Suggested tracker changes and task suggestions retain their existing review steps. The prototype does not add email sending or replying.
- Keep multiple email identities distinct from the primary Orbit identity, and retain message/provider provenance.
- Plaid connections and tokens follow the existing backend flow. The HTML does not connect a bank, authorize financial actions, or create a new backend capability.
- Keep automatic financial organization consent separate from sharing compact Finance context with chat and voice. Preserve manual classification precedence and separate currencies.
- Apple Health remains read-only. Health sharing with AI requires the existing explicit opt-in and sends derived summaries, not raw samples or identifiers.
- Body Load remains an app estimate based on recorded patterns. Do not present it as measured psychological stress, a diagnosis, or a new health score.
- Personal Memory remains reviewable and deletable. Suggested memories require approval; explicit supported memory commands retain their current behavior.
- `AutomationService` currently changes local configuration; schedule registration is not implemented there. Do not turn a sample toggle or frequency into a claim that monitoring is running.
- Keep existing destructive confirmations, credential storage, permission prompts, and voice lifecycle cleanup. Browser illustration code must not replace these service contracts.

## Native source anchors

Audit the current Swift sources before implementing; this guide is a snapshot and does not override newer code.

- `ios/JobRadar/JobRadar/Design/AppTheme.swift`: central palette, spacing, radii, and reusable styles.
- `ios/JobRadar/JobRadar/Views/MainTabView.swift`: dock, launcher gestures, More destinations, and sheet presentation.
- `ios/JobRadar/JobRadar/Views/Home/HomeView.swift`: dashboard hierarchy, quick capture, summaries, and calendar actions.
- `ios/JobRadar/JobRadar/Views/Tasks/TasksView.swift`: quick capture/editor, scheduling, completion, suggestions, and Undo.
- `ios/JobRadar/JobRadar/Views/Jobs/JobsView.swift` and `Views/Inbox/InboxView.swift`: tracker, review, filtering, and provenance.
- `ios/JobRadar/JobRadar/Views/Finance/FinanceView.swift`, `IncomeView.swift`, and `IncomeCalculatorView.swift`: financial detail and classifications.
- `ios/JobRadar/JobRadar/Views/Health/HealthView.swift`: health categories, estimates, detail, and consent.
- `ios/JobRadar/JobRadar/Views/Assistant/AssistantView.swift` and `LiveVoiceView.swift`: conversation, explicit commands, memory, and voice lifecycle.
- `ios/JobRadar/JobRadar/Views/Settings/SettingsView.swift`, `Views/Automations/AutomationsView.swift`, and `Services/AutomationService.swift`: account controls and automation limits.

## Preview verification

- Open `orbit-refined.html` directly, or serve the `design/` directory. No installation or build is required.
- `orbit-preview.png` is the desktop design-board screenshot.
- Checked all seven screens at 320, 390, 430, 820, 1024, and 1440 px widths for horizontal overflow.
- Exercised task creation/completion/Undo/search, job and mailbox filters, detail dialogs, financial periods/calculation, consent, chat/voice handoff, long presses, keyboard dismissal, and connection preview states.
- Verified direct-file operation and no external requests or browser JavaScript errors. Native code was not built for this HTML-only design task.

## Prompt for the implementation model

> Refine my existing Orbit iOS app using `design/orbit-refined.html` as the visual reference and `design/orbit-design-handoff.md` as the handoff. First compare both with the current Swift source and repository instructions. Implement the design in native SwiftUI, preserving the exact black/red identity, task-first Home, existing features, repositories, state handling, privacy controls, and consent. Match the HTML's typography hierarchy, spacing, grouped cards, restrained glow, and dock. Translate the 390 pt phone content only; exclude the desktop showcase, mock device chrome, sample data, and preview labels. Keep Home/Finance/Health/More navigation, Orbit tap-for-chat and hold-for-voice, secondary destinations, sheets, deep links, and accessibility. Treat HTML replies, balances, charts, connection indicators, and state transitions as illustrative; bind the interface to existing native data and services. Retain functionality not fully represented in the HTML, including detailed editors, review flows, source provenance, cached/error states, financial classification, all health categories, and settings. If visual simplification conflicts with current behavior, retain the behavior and adapt its presentation. Do not infer new backend capabilities from the mockup. Complete appropriate build and focused interaction checks, and report what was actually verified.
