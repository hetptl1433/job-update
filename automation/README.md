# Job Radar automation

Keeps the production tracker current without you in the loop.

## How it works

```text
  Gmail  ──────────────────────────────────────────────┐
    │                                                  │
    ▼                                                  │
  ChatGPT task  (daily, Gmail connector)               │  stage 1 — already built
    │  reads recruiting mail, decides what changed     │
    ▼                                                  │
  digest email  ── prose summary + JSON block ─────────┘
    │
    ▼
  Apps Script  (daily trigger, free)                   ┐
    │  1. find newest digest by sentinel               │
    │  2. GET /api/tracker      ← live cloud data      │
    │  3. reconcile, preserving manual edits           │  stage 2 — this directory
    │  4. PUT /api/tracker      → production updates   │
    │  5. commit both seed files to main               │
    │  6. verify production, check Vercel status       │
    ▼                                                  ┘
  https://job-update.vercel.app
```

Stage 1 was already working — it just stopped at your inbox. Stage 2 is what you
were doing by hand every morning, and is what stopped happening after July 29.

**No OpenAI API key and no per-run cost.** ChatGPT already did the reading and
judging inside your existing subscription, so stage 2 is a parser and a writer,
not a second model. Apps Script and its daily trigger are free.

## Why it writes the cloud, not just the seed

`api/tracker.js` deliberately preserves the existing Blob record over a duplicate
seed record, so your manual phone edits are never clobbered. That is correct
behaviour, and it has a consequence: **committing a status change to the seed
files alone is invisible in production.** Only brand-new companies surface that
way, which is exactly why Renesas and Formlabs appeared but a status change to
Western Digital never would.

So the script writes `interview-tracker/data.json` through authenticated `PUT`
first — that is what the site serves — and commits the seed files afterwards to
keep the fallback path accurate. Cloud first also means production is right even
if the GitHub step fails.

## Setup

### 1. Update the ChatGPT task

Open your existing daily task and replace its prompt with
[chatgpt-task-prompt.md](chatgpt-task-prompt.md). Leave the schedule alone.

The prompt must keep the literal string `JOBRADAR_SYNC_V1` — Gmail search is how
the script finds the digest, and nothing works without it.

While you are in there, confirm the task is still **enabled**. It may have been
auto-paused, which is worth ruling out before blaming stage 2.

### 2. Create a GitHub token

github.com → Settings → Developer settings → **Fine-grained personal access
tokens** → Generate new token.

- Repository access: **Only select repositories** → `hetptl1433/job-update`
- Permissions → Repository permissions → **Contents: Read and write**
- Nothing else. It does not need issues, actions, or workflow scope.

Copy the token now; GitHub will not show it again.

### 3. Create the Apps Script project

Go to [script.google.com](https://script.google.com) → **New project**. Sign in
as the Google account that receives the digests — `GmailApp` reads that
account's mail and nothing else.

Paste [sync-tracker.gs](sync-tracker.gs) over the default `Code.gs`.

### 4. Add the secrets

Project Settings (gear icon) → Script Properties → Add script property:

| Property | Required | Value |
|---|---|---|
| `GITHUB_TOKEN` | yes | the token from step 2 |
| `ADMIN_PASSWORD` | yes | the same `ADMIN_PASSWORD` set in your Vercel env vars |
| `PRODUCTION_URL` | see below | base URL of the deployment, no trailing slash |
| `VERCEL_BYPASS` | see below | Protection Bypass for Automation secret |

These live in Google's property store, not in this repository. Never commit them.

### 4a. Point at the right deployment

**`https://job-update.vercel.app` is not this app.** That hostname was claimed by
an unrelated create-react-app project and returns "React App" for every path,
including `/api/tracker`. Deployments of this repo go to the Vercel project
`hetptl1433s-projects/job-update`, currently served at:

```text
https://job-update-hetptl1433s-projects.vercel.app
```

Confirm the current alias under **Vercel → job-update → Domains**, and set
`PRODUCTION_URL` to it. The script fails with a specific error rather than a
JSON parse error if it gets HTML back, but it is worth getting right up front.

### 4b. Let the script past Deployment Protection

The project has **Vercel Authentication** enabled, which sits in front of the
entire deployment and is separate from `ADMIN_PASSWORD`. Unauthenticated
requests get a `302` to `vercel.com/sso-api`, so the script never reaches the
API at all. Pick one:

- **Recommended.** Vercel → Settings → Deployment Protection → **Protection
  Bypass for Automation** → generate a secret, and store it as `VERCEL_BYPASS`.
  Humans still hit SSO; the script passes it as `x-vercel-protection-bypass`.
- Or disable protection for Production. The tracker API still requires
  `ADMIN_PASSWORD`, but the rest of the deployment becomes publicly reachable.

### 5. Dry run

Run `checkConnection` first. Google will prompt for authorization the first time
— it needs Gmail read, external fetch, and mail send. It confirms the script can
reach both the tracker API and GitHub, and names the specific failure if not.
Get this green before going further; steps 1–4 are all it exercises.

Then run `dryRun` from the editor toolbar.

`dryRun` reads the digest and your live cloud data, prints what it *would*
change, and writes nothing. Check the execution log and confirm the companies
listed look right.

If it reports `No digest found`, stage 1 is the problem, not stage 2 — go back
to step 1.

### 6. Install the trigger

Run `installTrigger` once. That schedules `syncTracker` daily at ~7am, after your
ChatGPT task has run. Adjust `atHour(7)` if your task fires later.

You will get an email after each run that changes something, and an email if a
run fails. Silence means nothing changed that day.

## Safety

The prompt asks ChatGPT to behave; the script assumes it sometimes won't.
Regardless of what a digest contains, `syncTracker`:

- drops any field outside the allowed record schema
- strips URLs, email addresses, and long tokens from every value before writing
- refuses a digest carrying more than 8 changes as a likely bad parse
- never rewrites `company` or `role` on an existing record — those are the
  matching keys, and rewriting them would orphan the row
- never deletes a record, and aborts if reconciliation ends with fewer records
  than it started with
- applies only the fields a digest explicitly includes, so an omitted field
  keeps its current value
- refuses to run if `/api/tracker` reports cloud storage is unavailable, rather
  than writing a change that would not persist
- reads production back afterwards and reports any change that did not land

It only ever writes `main`. It does not touch `agent/ios-job-radar`.

## Verifying a run

```bash
# what the automation last committed
git log --oneline -3 --grep="verified recruiting digest"

# what production is actually serving
curl -s -H "x-admin-password: $ADMIN_PASSWORD" \
  https://job-update.vercel.app/api/tracker | python3 -m json.tool | head -40
```

## Troubleshooting

| Symptom | Cause |
|---|---|
| `Deployment Protection is blocking` | Set `VERCEL_BYPASS`, or disable protection — see step 4b |
| `returned HTML instead of JSON` | `PRODUCTION_URL` points at the wrong project — see step 4a |
| `No digest found` | ChatGPT task is paused, or its prompt lost the sentinel |
| `ADMIN_PASSWORD rejected` | Script property does not match the Vercel env var |
| `Refusing to sync: cloud storage is unavailable` | Blob store disconnected in Vercel |
| `GitHub /repos/... returned 403` | Token expired, or missing Contents: write |
| `Digest reported N changes, over the limit` | Likely a bad ChatGPT run — check the digest by hand |
| Runs fine, site looks stale | Hard-refresh; assets are versioned with `?v=` in `index.html` |
