import test from "node:test";
import assert from "node:assert/strict";
import { handler } from "../src/handler.js";
import { buildHostedLinkRequest, hostedLinkTokenHash } from "../src/plaid-service.js";

test("health route is public and reports the selected environment", async () => {
  process.env.PLAID_ENV = "production";
  const result = await handler({ routeKey: "GET /health" });
  assert.equal(result.statusCode, 200);
  assert.deepEqual(JSON.parse(result.body), {
    ok: true,
    service: "orbit-finance",
    environment: "production"
  });
});

test("AASA route returns the exact Orbit application identifier", async () => {
  process.env.APPLE_APP_ID = "TEAM123.com.hetpatel.jobradar";
  const result = await handler({ routeKey: "GET /.well-known/apple-app-site-association" });
  assert.equal(result.statusCode, 200);
  const body = JSON.parse(result.body);
  assert.deepEqual(body.applinks.details[0].appIDs, ["TEAM123.com.hetpatel.jobradar"]);
});

test("authenticated routes reject requests without a validated Google subject", async () => {
  const result = await handler({ routeKey: "GET /api/plaid/overview", requestContext: {} });
  assert.equal(result.statusCode, 401);
  assert.equal(JSON.parse(result.body).error, "Sign in to Orbit again.");
});

test("income routes require authentication before reading financial data", async () => {
  const result = await handler({
    routeKey: "POST /api/finance/income",
    body: JSON.stringify({ asOfDate: "2026-08-09", timeZone: "UTC" }),
    requestContext: {}
  });
  assert.equal(result.statusCode, 401);
  assert.equal(JSON.parse(result.body).error, "Sign in to Orbit again.");
});

test("income summary validates local date and IANA time zone before storage access", async () => {
  const event = {
    routeKey: "POST /api/finance/income",
    body: JSON.stringify({ asOfDate: "2026-02-29", timeZone: "Not/AZone" }),
    requestContext: { authorizer: { jwt: { claims: { sub: "google-user-123" } } } }
  };
  const result = await handler(event);
  assert.equal(result.statusCode, 400);
  assert.match(JSON.parse(result.body).error, /asOfDate/);
});

test("income classification rejects malformed IDs and decisions before storage access", async () => {
  const auth = { authorizer: { jwt: { claims: { sub: "google-user-123" } } } };
  const malformedPath = await handler({
    routeKey: "POST /api/finance/income/transactions/{id}/classification",
    pathParameters: { id: "%E0%A4%A" },
    body: JSON.stringify({ classification: "income" }),
    requestContext: auth
  });
  assert.equal(malformedPath.statusCode, 400);

  const invalidDecision = await handler({
    routeKey: "POST /api/finance/income/transactions/{id}/classification",
    pathParameters: { id: "valid-transaction-id" },
    body: JSON.stringify({ classification: "probably" }),
    requestContext: auth
  });
  assert.equal(invalidDecision.statusCode, 400);
  assert.match(JSON.parse(invalidDecision.body).error, /income or notIncome/);

  const missingLocalDate = await handler({
    routeKey: "POST /api/finance/income/transactions/{id}/classification",
    pathParameters: { id: "valid-transaction-id" },
    body: JSON.stringify({ classification: "income" }),
    requestContext: auth
  });
  assert.equal(missingLocalDate.statusCode, 400);
  assert.match(JSON.parse(missingLocalDate.body).error, /asOfDate/);
});

test("Hosted Link creation requires an authenticated Orbit user", async () => {
  const result = await handler({ routeKey: "POST /api/plaid/hosted-link", requestContext: {} });
  assert.equal(result.statusCode, 401);
  assert.equal(JSON.parse(result.body).error, "Sign in to Orbit again.");
});

test("Hosted Link status rejects malformed connection IDs before storage access", async () => {
  const result = await handler({
    routeKey: "GET /api/plaid/hosted-link/{id}",
    pathParameters: { id: "not-a-connection" },
    requestContext: { authorizer: { jwt: { claims: { sub: "google-user-123" } } } }
  });
  assert.equal(result.statusCode, 400);
  assert.equal(JSON.parse(result.body).error, "A valid Hosted Link connection ID is required.");
});

test("Hosted Link completion page offers an explicit Orbit deep-link fallback", async () => {
  const result = await handler({ routeKey: "GET /plaid/complete" });
  assert.equal(result.statusCode, 200);
  assert.match(result.headers["content-security-policy"], /default-src 'none'/);
  assert.match(result.body, /href="orbit:\/\/finance"/);
  assert.doesNotMatch(result.body, /public-/);
});

test("Plaid OAuth return page offers a manual Orbit deep-link fallback", async () => {
  const result = await handler({ routeKey: "GET /plaid/oauth" });
  assert.equal(result.statusCode, 200);
  assert.match(result.headers["content-security-policy"], /default-src 'none'/);
  assert.match(result.body, /href="orbit:\/\/finance"/);
});

test("Hosted Link ownership keys hash the short-lived Link token", () => {
  const token = "link-production-7ee428d9-54d1-4fde-b49c-f6ed725f5f28";
  const hash = hostedLinkTokenHash(token);
  assert.match(hash, /^[a-f0-9]{64}$/);
  assert.equal(hash, hostedLinkTokenHash(token));
  assert.notEqual(hash, token);
});

test("mobile Hosted Link includes both required Plaid redirect URIs", () => {
  const request = buildHostedLinkRequest("google-user-123", {
    webhookURL: "https://api.ipodeskai.com/api/plaid/webhook",
    redirectURI: "https://api.ipodeskai.com/plaid/oauth",
    hostedLinkCompletionURI: "orbit://finance"
  });
  assert.equal(request.hosted_link.is_mobile_app, true);
  assert.equal(request.hosted_link.completion_redirect_uri, "orbit://finance");
  assert.equal(request.hosted_link.url_lifetime_seconds, 1_800);
  assert.equal(request.redirect_uri, "https://api.ipodeskai.com/plaid/oauth");
  assert.equal(request.transactions.days_requested, 365);
  assert.match(request.user.client_user_id, /^orbit_[a-f0-9]{40}$/);
});
