# Job Radar for iPhone

Native SwiftUI app for Het's interview pipeline. The project lives on the `agent/ios-job-radar` branch so the existing Vercel website remains untouched.

## Included

- SwiftUI status radar designed for iPhone, not a web wrapper
- SwiftData offline database
- Refresh and save against the existing `/api/tracker` backend
- Admin password stored in iOS Keychain
- Per-company local follow-up notifications
- 6:00 AM local digest notification
- APNs device-token registration hook
- Background refresh hook using `BGAppRefreshTask`
- Sign in with Apple
- OAuth connection UI for Gmail, LinkedIn, and Indeed
- GitHub Actions simulator build

## Generate and open the Xcode project

```bash
brew install xcodegen
cd ios/JobRadar
xcodegen generate
open JobRadar.xcodeproj
```

In Xcode:

1. Select the `JobRadar` target and choose your Apple Developer Team.
2. Change `com.hetpatel.jobradar` if that bundle identifier is unavailable.
3. Confirm **Push Notifications**, **Background Modes** (`Background fetch`, `Remote notifications`), and **Sign in with Apple** capabilities.
4. Update `APIBaseURL` in `JobRadar/Resources/Info.plist` to the production Vercel URL.
5. Run on a real iPhone to test remote notification registration.

## Integration reality

### Gmail

This is the primary automation source. The backend uses Google OAuth with offline access, retains refresh tokens securely, scans only recruiting messages, updates `/api/tracker`, and can send APNs when a verified status changes.

### LinkedIn

OpenID Connect can sign the user in and return basic profile/email. Reading LinkedIn inbox messages or application history requires separate approved permissions that are not generally available through basic sign-in. Do not scrape LinkedIn.

### Indeed

Indeed OAuth requires an approved partner application. Basic login is possible after credentials are issued, but job-seeker application-history access is not a standard public feed. Do not scrape Indeed.

### Exact 6:00 AM automation

The local digest is scheduled for 6:00 AM. iOS background refresh is system-controlled and is not guaranteed at an exact minute. Exact status-change alerts must come from the server through APNs after the Gmail automation runs.

## Backend endpoints

- `GET /api/tracker`
- `PUT /api/tracker`
- `POST /api/mobile/push/register`
- `POST /api/mobile/push/send`
- `GET /api/mobile/oauth/gmail/start`
- `GET /api/mobile/oauth/linkedin/start`
- `GET /api/mobile/oauth/indeed/start`

## Vercel environment variables

- `OAUTH_STATE_SECRET`
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`
- `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`
- `INDEED_CLIENT_ID`, `INDEED_CLIENT_SECRET`
- `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`
- `APNS_ENVIRONMENT` (`development` or `production`)

OAuth refresh/access tokens and APNs device tokens are written to private Vercel Blob objects. Never commit provider secrets or Apple `.p8` keys.
