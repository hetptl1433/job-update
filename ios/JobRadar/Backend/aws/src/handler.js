import { HTTPError, publicError, safeErrorLog } from "./errors.js";
import { plaidEnvironment } from "./config.js";
import { classifyIncomeTransaction, getIncomeOverview } from "./income-service.js";
import {
  createHostedLink,
  createLinkToken,
  disconnectItem,
  exchangePublicToken,
  getOverview,
  getHostedLinkStatus,
  handlePlaidWebhook,
  syncAllItems
} from "./plaid-service.js";

const JSON_HEADERS = Object.freeze({
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff"
});

function response(statusCode, body, headers = {}) {
  return {
    statusCode,
    headers: { ...JSON_HEADERS, ...headers },
    body: JSON.stringify(body)
  };
}

function rawBody(event) {
  const body = event.body ?? "";
  return event.isBase64Encoded ? Buffer.from(body, "base64").toString("utf8") : body;
}

function jsonBody(event) {
  const body = rawBody(event);
  if (!body) return {};
  if (Buffer.byteLength(body, "utf8") > 32_768) throw new HTTPError(413, "The request body is too large.");
  try {
    return JSON.parse(body);
  } catch {
    throw new HTTPError(400, "The request body must be valid JSON.");
  }
}

function authenticatedUser(event) {
  const subject = event.requestContext?.authorizer?.jwt?.claims?.sub;
  if (typeof subject !== "string" || subject.length < 3 || subject.length > 255) {
    throw new HTTPError(401, "Sign in to Orbit again.");
  }
  return subject;
}

function decodedPathParameter(event, name) {
  const raw = event.pathParameters?.[name];
  if (typeof raw !== "string") return "";
  try {
    return decodeURIComponent(raw);
  } catch {
    throw new HTTPError(400, "The request path contains an invalid identifier.");
  }
}

function appleAssociation() {
  const appID = process.env.APPLE_APP_ID;
  if (!appID) throw new HTTPError(503, "APPLE_APP_ID must be configured before enabling Chase OAuth.");
  return response(200, {
    applinks: {
      details: [{
        appIDs: [appID],
        components: [{ "/": "/plaid/*", comment: "Orbit Plaid OAuth return" }]
      }]
    }
  }, { "cache-control": "public, max-age=300" });
}

function oauthLanding() {
  return {
    statusCode: 200,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff"
    },
    body: `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Return to Orbit</title>
  <style>
    :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
    body { min-height: 100vh; margin: 0; display: grid; place-items: center; background: #080808; color: #f7f7f7; }
    main { width: min(30rem, calc(100% - 3rem)); text-align: center; }
    .orbit { width: 3rem; height: 3rem; margin: 0 auto 1.5rem; border: 1px solid #777; border-radius: 50%; position: relative; }
    .orbit::after { content: ""; width: .55rem; height: .55rem; background: #fff; border-radius: 50%; position: absolute; right: -.2rem; top: .35rem; }
    h1 { margin: 0 0 .75rem; font-size: 1.8rem; letter-spacing: -.03em; }
    p { color: #aaa; line-height: 1.5; margin: 0 0 1.75rem; }
    a { display: inline-block; padding: .85rem 1.2rem; border-radius: 999px; background: #fff; color: #080808; text-decoration: none; font-weight: 650; }
  </style>
</head>
<body>
  <main>
    <div class="orbit" aria-hidden="true"></div>
    <h1>Return to Orbit</h1>
    <p>Your bank sent you back securely. Open Orbit to continue checking the connection.</p>
    <a href="orbit://finance">Open Orbit</a>
  </main>
</body>
</html>`
  };
}

function hostedLinkCompletion() {
  return {
    statusCode: 200,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff"
    },
    body: `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Return to Orbit</title>
  <style>
    :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
    body { min-height: 100vh; margin: 0; display: grid; place-items: center; background: #080808; color: #f7f7f7; }
    main { width: min(30rem, calc(100% - 3rem)); text-align: center; }
    .orbit { width: 3rem; height: 3rem; margin: 0 auto 1.5rem; border: 1px solid #777; border-radius: 50%; position: relative; }
    .orbit::after { content: ""; width: .55rem; height: .55rem; background: #fff; border-radius: 50%; position: absolute; right: -.2rem; top: .35rem; }
    h1 { margin: 0 0 .75rem; font-size: 1.8rem; letter-spacing: -.03em; }
    p { color: #aaa; line-height: 1.5; margin: 0 0 1.75rem; }
    a { display: inline-block; padding: .85rem 1.2rem; border-radius: 999px; background: #fff; color: #080808; text-decoration: none; font-weight: 650; }
  </style>
</head>
<body>
  <main>
    <div class="orbit" aria-hidden="true"></div>
    <h1>Bank connection finished</h1>
    <p>Orbit is securely processing the connection. Return to Finance, then refresh if the account takes a moment to appear.</p>
    <a href="orbit://finance">Open Orbit</a>
  </main>
</body>
</html>`
  };
}

export async function handler(event) {
  const routeKey = event.routeKey ?? `${event.requestContext?.http?.method ?? ""} ${event.rawPath ?? ""}`;
  try {
    switch (routeKey) {
    case "GET /health":
      return response(200, { ok: true, service: "orbit-finance", environment: plaidEnvironment() });
    case "GET /.well-known/apple-app-site-association":
      return appleAssociation();
    case "GET /plaid/oauth":
      return oauthLanding();
    case "GET /plaid/complete":
      return hostedLinkCompletion();
    case "POST /api/plaid/webhook": {
      const body = rawBody(event);
      if (Buffer.byteLength(body, "utf8") > 262_144) {
        throw new HTTPError(413, "The webhook body is too large.");
      }
      await handlePlaidWebhook(body, event.headers);
      return response(200, { received: true });
    }
    case "POST /api/plaid/hosted-link": {
      const hostedLink = await createHostedLink(authenticatedUser(event));
      return response(200, hostedLink);
    }
    case "GET /api/plaid/hosted-link/{id}": {
      const connectionID = decodeURIComponent(event.pathParameters?.id ?? "");
      const status = await getHostedLinkStatus(authenticatedUser(event), connectionID);
      return response(200, { data: status });
    }
    case "POST /api/plaid/link-token": {
      const linkToken = await createLinkToken(authenticatedUser(event));
      return response(200, { linkToken });
    }
    case "POST /api/plaid/exchange-public-token": {
      const overview = await exchangePublicToken(authenticatedUser(event), jsonBody(event).publicToken);
      return response(200, { data: overview });
    }
    case "GET /api/plaid/overview": {
      const overview = await getOverview(authenticatedUser(event));
      return response(200, { data: overview });
    }
    case "POST /api/plaid/transactions/sync": {
      const overview = await syncAllItems(authenticatedUser(event));
      return response(200, { data: overview });
    }
    case "POST /api/finance/income": {
      const overview = await getIncomeOverview(authenticatedUser(event), jsonBody(event));
      return response(200, { data: overview });
    }
    case "POST /api/finance/income/transactions/{id}/classification": {
      const userSub = authenticatedUser(event);
      const transactionID = decodedPathParameter(event, "id");
      const overview = await classifyIncomeTransaction(userSub, transactionID, jsonBody(event));
      return response(200, { data: overview });
    }
    case "DELETE /api/plaid/items/{id}": {
      const itemID = decodeURIComponent(event.pathParameters?.id ?? "");
      await disconnectItem(authenticatedUser(event), itemID);
      return response(200, { removed: true });
    }
    default:
      throw new HTTPError(404, "Route not found.");
    }
  } catch (error) {
    const safe = publicError(error);
    if (safe.statusCode >= 500) console.error(JSON.stringify(safeErrorLog(error, routeKey)));
    return response(safe.statusCode, { error: safe.message });
  }
}
