# Orbit Plaid backend

Plaid credentials and Item access tokens are server-only. The iOS app must
receive a short-lived Link token from this backend; it must never contain the
Plaid secret or a Plaid Item access token.

`Backend/.env.local` contains the current local development credentials and is
ignored by Git. A deployed backend must use its provider's encrypted secret
store instead of uploading this file.

The deployable AWS implementation lives in `Backend/aws`. It provides these
routes before the iOS connection can work:

- `POST /api/plaid/link-token`
- `POST /api/plaid/exchange-public-token`
- `POST /api/plaid/transactions/sync`
- `GET /api/plaid/overview`
- `POST /api/plaid/webhook`
- `DELETE /api/plaid/items/:id`
- `POST /api/finance/income`
- `POST /api/finance/income/transactions/:id/classification`

Every user-facing finance route validates the Google ID token from the
`Authorization: Bearer` header and scopes every Plaid Item to that Google
subject. Never accept a user ID from the request body as proof of identity. The
public webhook route instead validates Plaid's signed JWT and exact request-body
hash. Health, OAuth landing, and Apple association routes contain no user data.

`POST /api/plaid/link-token` returns:

```json
{ "linkToken": "link-sandbox-or-production-token" }
```

`POST /api/plaid/exchange-public-token` accepts `{ "publicToken": "..." }` and
returns the same overview envelope as `GET /api/plaid/overview`:

```json
{
  "data": {
    "institutions": [],
    "accounts": [],
    "recentTransactions": [],
    "monthlyInflow": 0,
    "monthlyOutflow": 0,
    "totalCash": 0,
    "totalCreditBalance": 0,
    "totalInvestments": 0,
    "recurringPayments": [],
    "monthlyRecurringTotal": 0,
    "spendingByCategory": [],
    "currencyCode": "USD",
    "lastUpdatedAt": "2026-08-09T00:00:00Z"
  }
}
```

`recurringPayments` contains conservative cadence-based estimates from posted
outflows, including monthly-equivalent amounts and the next expected date.
`spendingByCategory` contains the six largest posted outflow categories for the
current month. Pending transactions are excluded from both insights.

Normalize each transaction to a positive `amount` plus an explicit `direction`
of `inflow` or `outflow`. Use Plaid `date` as the posted date and retain
`authorized_date` separately as `authorizedDate`; authorization timing must not
move a posted transaction between reporting months. Do not send Plaid's raw
amount sign convention to the app. `DELETE /api/plaid/items/:id` must call
Plaid `/item/remove`, erase the encrypted token and cached financial data, and
return `{ "removed": true }`.

The income contract and classification precedence are documented in
`Backend/aws/README.md`. Income reads all stored records, separates posted,
pending, and review amounts, groups by currency, and persists user decisions in
separate user-partitioned DynamoDB records so Plaid sync cannot overwrite them.

Chase OAuth uses `https://api.ipodeskai.com/plaid/oauth`. The backend serves the
Apple App Site Association file for that host, and Orbit declares
`applinks:api.ipodeskai.com` in its Associated Domains entitlement.
