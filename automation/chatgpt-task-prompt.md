# ChatGPT task prompt

Replace the prompt in your existing daily ChatGPT task with the text below.

The only structural change from what you had: it must end with a JSON block
carrying the sentinel `JOBRADAR_SYNC_V1`. The Apps Script finds the digest by
searching Gmail for that exact string, so it has to appear verbatim. The prose
summary above the block is untouched and is still what you read in the morning —
the script ignores everything except the JSON.

---

```text
Every day, review my Gmail for recruiting email about jobs I have actually
applied to, received since your last run.

INCLUDE:
- Interview invitations and recruiter screens
- Scheduling and rescheduling messages
- Technical assessments and one-way video interviews
- Responses to my follow-ups
- Rejections, offers, onboarding, and final decisions
- LinkedIn recruiter and InMail notifications about a specific application

IGNORE:
- General job alerts and recommended-job digests
- Marketing, promotions, and learning newsletters
- Ordinary "we received your application" confirmations
- Bulk recruiter blasts not tied to an application of mine

An application confirmation only counts if it advances the application into an
interview, assessment, offer, onboarding, or final decision.

For each application whose state actually changed, choose:

status: one of
  "Need Status Update", "Interview Scheduled", "Assessment / Next Round",
  "Offer Received", "Offer Accepted / Active", "Rejected", "Withdrawn"

stage: one of
  "Recruiter Screen", "Technical Assessment", "One-way Video",
  "Hiring Manager Interview", "Final Interview", "Final Decision",
  "Offer / Onboarding"

priority: "High", "Medium", or "Low"
nextAction: what I should do next, or "Closed." if nothing remains
dates: YYYY-MM-DD, or "" when unknown

Common mappings:
  Interview invitation -> stage "Recruiter Screen", status "Interview Scheduled",
    priority "High", nextAction "Prepare for the scheduled recruiter interview."
  Assessment -> stage "Technical Assessment", status "Assessment / Next Round",
    priority "High", nextAction "Complete the assessment before the deadline."
  Rejection -> stage "Final Decision", status "Rejected", priority "Low",
    nextAction "Closed.", followUpDate ""
  Offer -> stage "Offer / Onboarding", status "Offer Received", priority "High",
    nextAction "Review the offer and respond before the deadline."

First write me a short plain-language summary of what changed and what needs my
attention today.

Then output this exact block, and nothing after it:

JOBRADAR_SYNC_V1

```json
{
  "schema": "JOBRADAR_SYNC_V1",
  "generatedAt": "YYYY-MM-DD",
  "changes": [
    {
      "company": "Example Corp",
      "role": "Exact role title as written in the email",
      "stage": "Final Decision",
      "status": "Rejected",
      "priority": "Low",
      "nextAction": "Closed.",
      "followUpDate": "",
      "notes": "One sentence citing what the email said and its date."
    }
  ]
}
```

RULES FOR THE JSON BLOCK

Only include applications that changed. If nothing changed, use "changes": [].

Never include more than 8 changes. If more seem to qualify, keep the 8 most
consequential and say so in the summary.

"company" and "role" are required on every entry, and must match the wording
used in earlier digests for the same application so it updates the existing row
rather than creating a duplicate.

Include ONLY the fields the email actually verifies. Omitted fields keep their
current value, so omission is always the safe choice. A rejection email
justifies status, stage, nextAction, followUpDate, and notes — it does NOT
justify rewriting priority, interviewDate, mode, role, or contact.

Allowed fields, and nothing else:
  company, role, stage, inviteDate, interviewDate, status, priority,
  nextAction, followUpDate, contact, mode, source, notes

PRIVACY — this goes into a public GitHub repository:
- Never include Gmail links, message IDs, thread IDs, or tokens
- Never include full email bodies or quoted text
- Never include personal names or email addresses
- Use generic contacts only: "Formlabs recruiting", "Western Digital
  recruiting", "LinkedIn recruiter", "Company hiring team"
- Keep notes to one short factual sentence

Base every entry on an email you actually found. Never infer a rejection from
silence, and never invent a change to fill a quiet day.
```

---

## Why JSON

The old digest was readable but ambiguous. "Heard back from Formlabs, looks like
a no" doesn't tell a script which record to touch or what to set it to, and
guessing at that is where this kind of pipeline breaks silently. The JSON block
makes stage 2 a parser rather than an inference, which is what lets it run
unattended with no second model — and no second bill — in the loop.

## What the script enforces regardless

The prompt asks ChatGPT to behave, and the script assumes it sometimes won't.
Independently of what the digest says, `sync-tracker.gs`:

- drops any field not on the allowed list
- strips URLs, email addresses, and long tokens out of every value
- refuses a digest carrying more than 8 changes as a likely bad parse
- never rewrites `company` or `role` on an existing record, since those are the
  matching keys and rewriting them would orphan the row
- never deletes a record
- aborts if reconciliation ends up with fewer records than it started with
