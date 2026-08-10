# Orbit Finance on AWS

This directory deploys Orbit's Plaid backend as an AWS serverless stack:

- API Gateway HTTP API with a Google ID-token JWT authorizer
- one Node.js Lambda function
- DynamoDB pay-per-request storage
- a customer-managed KMS key for Plaid Item access tokens
- Secrets Manager access for the existing Plaid credentials
- public, signed Plaid webhook handling
- short-lived, user-scoped Plaid Hosted Link sessions for free Apple Personal Teams
- deterministic income classification, source detection, and currency-scoped summaries
- separate, user-scoped income decisions that Plaid transaction sync cannot overwrite

No Plaid secret or permanent access token is returned to the iPhone.

## Prerequisites

1. Install AWS CLI v2 and AWS SAM CLI.
2. Sign in with `aws configure sso` and verify with `aws sts get-caller-identity`.
3. Create the Plaid secret in the same AWS region as the stack. Copy its ARN,
   not its value.
4. Own an HTTPS endpoint for Plaid webhooks. The deployed
   `https://api.ipodeskai.com` custom domain satisfies this requirement.
5. An Apple Team ID and Associated Domains are required only for the original
   native Plaid SDK/Universal Link flow. They are not required for the
   developer-only Hosted Link flow described below.

The Secrets Manager JSON must contain:

```json
{
  "PLAID_CLIENT_ID": "stored-in-aws",
  "PLAID_SECRET": "stored-in-aws"
}
```

`PLAID_ENV` is a deployment parameter, not a secret. The current Plaid Trial
uses `production` and real financial data.

## Deploy

From this directory:

```bash
npm ci
npm test
sam validate --lint
sam build
sam deploy --guided
```

Use these guided values:

```text
Stack name: orbit-finance-production
Region: us-east-2
PlaidSecretArn: ARN copied from Secrets Manager
PlaidEnvironment: production
GoogleClientID: Orbit's existing Google iOS client ID
PlaidRedirectURI: https://api.ipodeskai.com/plaid/oauth
PlaidWebhookURL: https://api.ipodeskai.com/api/plaid/webhook
HostedLinkCompletionURI: orbit://finance
AppleAppID: VN6463GX9K.com.hetpatel.jobradar
Allow SAM CLI IAM role creation: Yes
Disable rollback: No
Save arguments to configuration file: Yes
```

Do not put the Plaid secret itself into a SAM parameter. The generated
`samconfig.toml` is ignored by Git because it contains account-specific values.

## Configure the custom domain

The first deployment outputs an API Gateway URL. Configure the custom domain so
Plaid can reach the signed webhook endpoint:

1. Request an ACM certificate in `us-east-2` for `api.ipodeskai.com`.
2. In API Gateway, create the Regional custom domain `api.ipodeskai.com` with
   that certificate.
3. Map the custom domain's root path to the generated Orbit HTTP API and its
   `$default` stage.
4. Add the API Gateway alias record to the domain's DNS.
5. Confirm these URLs return without a redirect:
   - `https://api.ipodeskai.com/health`
   - `https://api.ipodeskai.com/.well-known/apple-app-site-association`
   - `https://api.ipodeskai.com/plaid/complete`
6. Register `https://api.ipodeskai.com/plaid/oauth` under Plaid Dashboard's
   allowed redirect URIs.
7. Add `applinks:api.ipodeskai.com` only when using the original native Plaid
   SDK flow with a paid Apple Developer team. Do not add it for Hosted Link on
   a free Personal Team.

The AASA endpoint returns `503` until `AppleAppID` is configured. This avoids
Apple caching an empty association file.

## Connect Orbit

Set the deployed custom URL in the root `project.yml`:

```yaml
FinanceAPIBaseURL: "https://api.ipodeskai.com/"
```

Keep `APIBaseURL` empty unless a separate backend implements Orbit's optional
job tracker and push routes.

Regenerate the Xcode project and rebuild:

```bash
xcodegen generate
```

The app sends its refreshed Google ID token in the `Authorization` header.
API Gateway validates the Google signature, issuer, expiry, and iOS client-ID
audience before Lambda runs. Lambda scopes every DynamoDB record to the token's
stable `sub` claim.

### Free Apple Personal Team: Hosted Link

The authenticated app calls `POST /api/plaid/hosted-link`. Lambda creates a
30-minute Plaid Hosted Link session with these important properties:

- `hosted_link.is_mobile_app` is `true`.
- `hosted_link.completion_redirect_uri` is `orbit://finance`.
- the top-level `redirect_uri` is the allowlisted
  `https://api.ipodeskai.com/plaid/oauth` URL. Plaid requires both URI fields
  when `hosted_link.is_mobile_app` is `true`.

The iPhone opens the returned `hostedLinkURL` in `ASWebAuthenticationSession`
or external Safari. Plaid returns to Orbit with its custom URL scheme when the
session finishes. This does not require Apple's Associated Domains entitlement.

On a free Apple Personal Team, iOS does not claim that HTTPS redirect as a
Universal Link, so Chase may use a browser-first flow and the redirect can open
the hosted fallback page before Plaid finishes. The final Hosted Link callback
still uses `orbit://finance`. This is appropriate for a personal/demo build,
but a public production app should use a paid Apple Developer membership and
Associated Domains for reliable bank app-to-app OAuth.

Orbit never receives or stores the raw Hosted Link token. The server stores a
SHA-256 hash mapped to the authenticated Google `sub`, a random connection ID,
and an enforced expiration. DynamoDB TTL removes the mapping later. Plaid sends
a signed `LINK/ITEM_ADD_RESULT` or `LINK/SESSION_FINISHED` webhook; only after
signature, environment, token ownership, expiration, and replay checks pass
does Lambda exchange the public token. The webhook performs only the lightweight
token exchange and encrypted Item save so it can answer Plaid quickly. Orbit
then calls the authenticated transaction sync endpoint.

The creation response is:

```json
{
  "hostedLinkURL": "https://secure.plaid.com/link/...",
  "connectionID": "4b6947f1-7096-4fce-8c79-b16d9eb3ed80",
  "expiresAt": "2026-08-09T23:00:00.000Z"
}
```

Poll `GET /api/plaid/hosted-link/{connectionID}` after Orbit becomes active.
Its `data.status` is one of `pending`, `processing`, `complete`, `exited`,
`failed`, or `expired`. The public `/plaid/complete` page provides a manual
**Open Orbit** button as a fallback; it contains no user or financial data.

## Routes

Authenticated with Google:

- `POST /api/plaid/hosted-link`
- `GET /api/plaid/hosted-link/{id}`
- `POST /api/plaid/link-token`
- `POST /api/plaid/exchange-public-token`
- `GET /api/plaid/overview`
- `POST /api/plaid/transactions/sync`
- `DELETE /api/plaid/items/{id}`
- `POST /api/finance/income`
- `POST /api/finance/income/transactions/{id}/classification`

Public by design:

- `POST /api/plaid/webhook` - verifies Plaid's ES256 signature, age, and body hash
- `GET /health`
- `GET /.well-known/apple-app-site-association`
- `GET /plaid/oauth`
- `GET /plaid/complete` - generic `orbit://finance` fallback page

Opening Plaid Link again connects another institution. Each connection remains
owned by the same authenticated Orbit user.

## Income API

Income is calculated from every normalized transaction stored for the
authenticated Google subject. It is not calculated from the 50-item recent
activity response and it is not interchangeable with gross inflow.

Call `POST /api/finance/income` with the device's local calendar date and IANA
time-zone identifier:

```json
{
  "asOfDate": "2026-08-09",
  "timeZone": "America/Indiana/Indianapolis"
}
```

Both fields are required and validated. Plaid's date-only `date` is the posted
date used for month and year boundaries. `authorizedDate` is retained only as
transaction context. Future-dated records are not included in an as-of result.

The response is grouped by currency; unlike currencies are never summed:

```json
{
  "data": {
    "summaries": [
      {
        "currencyCode": "USD",
        "basis": "observedNetDeposit",
        "thisMonth": { "confirmed": 5420, "pending": 1200, "needsReview": 350 },
        "lastMonth": { "confirmed": 5110, "pending": 0, "needsReview": 0 },
        "changeAmount": 310,
        "changePercent": 6.066536,
        "yearToDate": 39840,
        "averageMonthly": 4980,
        "estimatedAnnual": 59760,
        "sources": [],
        "history": [],
        "confirmedTransactions": [],
        "needsReviewTransactions": [],
        "projectedMonthEnd": 6620,
        "projectedYearEnd": 60240,
        "expectedPaychecks": [],
        "coverage": {
          "startDate": "2026-01-01",
          "endDate": "2026-08-09",
          "completeMonths": 7
        }
      }
    ],
    "lastUpdatedAt": "2026-08-09T18:42:00.000Z"
  }
}
```

`coverage.startDate` is `null` when a currency has an account but no stored
transactions. Each source contains `id`, `name`, `type`, `accountID`,
`frequency`, `averagePayment`, `averageMonthly`, `lastPaymentDate`,
`nextExpectedPaymentDate`, `active`, `confidence`, `userConfirmed`,
`thisMonth`, `yearToDate`, and `transactionCount`. Source types are `salary`,
`hourly`, `contract`, `freelance`, `consulting`, `business`, `bonus`,
`commission`, `interest`, `dividend`, and `other`. Frequencies are `weekly`,
`biweekly`, `semimonthly`, `monthly`, `irregular`, and `oneTime`.

History entries contain `month`, `confirmed`, `pending`, and `needsReview`.
Income transaction entries contain `id`, `accountID`, posted `date`, optional
`authorizedDate`, `name`, optional `merchantName` and `category`, positive
`amount`, explicit `direction`, `pending`, `currencyCode`, optional source
fields, `confidence`, `classificationReason`, `userConfirmed`, and
`classification`. Expected-paycheck entries contain `sourceID`, `sourceName`,
`date`, `estimatedAmount`, and `confidence`.

Summary, source, and returned transaction records explicitly use
`basis: "observedNetDeposit"`. These amounts are deposits observed in the bank
feed. They are not gross compensation and are never mixed with manually entered
gross salary or tax estimates.

`changePercent` is `null` when last month's confirmed income is zero.
Annualization and projections are also `null` unless at least three posted
payments establish an active regular pattern; ambiguous two-pay-period
cadences require at least four. Weekly, biweekly, semimonthly, and monthly
annualization use 52, 26, 24, and 12 periods respectively. All projections are
data estimates, never guarantees or tax advice.

To classify a specific incoming transaction, call:

```text
POST /api/finance/income/transactions/{transactionID}/classification
```

with:

```json
{
  "classification": "income",
  "sourceName": "Dometic",
  "type": "salary",
  "asOfDate": "2026-08-09",
  "timeZone": "America/Indiana/Indianapolis"
}
```

`classification` is exactly `income` or `notIncome`; `sourceName` and `type`
are optional. `asOfDate` and `timeZone` are required so the returned summary
uses the same local period as the originating screen, including around UTC
midnight. The compatibility alias `sourceType` is accepted, but new clients
should send `type`. The route returns the same `{ "data": IncomeOverview }`
envelope as the summary route.

The decision is saved in a separate DynamoDB item under the authenticated
user's partition, never inside the Plaid transaction item. A sync therefore
cannot overwrite it. A transaction-specific decision wins. Exact normalized
descriptors may carry that decision only to transactions posted on or after
the confirmed transaction; a later transaction-specific decision still wins.
Plaid's pending-to-posted ID link also carries the exact pending decision to
its posted replacement.

Without a user decision, own-account transfer pairs, transfer categories,
refunds/returns/reversals, loan proceeds, and reimbursements are excluded.
P2P and otherwise unknown deposits are review items. Keyword-only payroll or
direct-deposit text is also review-only. Only a specific Plaid income category
with high or very-high provider confidence is automatically confirmed.

## Production safety

- Never log request bodies, public tokens, access tokens, credentials, or raw
  financial provider responses.
- Keep Sandbox and Production DynamoDB stacks separate if Sandbox is added.
- Rotate any Plaid secret that has been exposed in screenshots or chat before
  connecting a real institution.
- `sam delete` removes the table and KMS key created by this stack. Export or
  disconnect data first if it must be retained.
