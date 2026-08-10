import { createHash, randomUUID, timingSafeEqual } from "node:crypto";
import { decodeProtectedHeader, importJWK, jwtVerify } from "jose";
import { CountryCode, Products } from "plaid";
import { getPlaidClient, getServerConfig } from "./config.js";
import { HTTPError, plaidErrorCode, safeErrorLog } from "./errors.js";
import { buildOverview, normalizeAccount, normalizeTransaction } from "./normalization.js";
import {
  applyTransactionChanges,
  claimHostedPublicToken,
  completeHostedPublicToken,
  deleteItemData,
  findItemOwner,
  getHostedLinkSessionByTokenHash,
  getHostedLinkSessionForUser,
  getUserItem,
  listUserItems,
  listUserRecords,
  markItemNeedsAttention,
  releaseHostedPublicToken,
  saveAccounts,
  saveHostedLinkSession,
  savePlaidItem,
  updateHostedLinkSession,
  updateItemSyncState
} from "./store.js";
import { decryptAccessToken, encryptAccessToken } from "./token-crypto.js";

function pseudonymousClientUserID(userSub) {
  return `orbit_${createHash("sha256").update(`orbit:${userSub}`).digest("hex").slice(0, 40)}`;
}

export function hostedLinkTokenHash(token) {
  if (typeof token !== "string" || !token.startsWith("link-") || token.length > 512) {
    throw new HTTPError(400, "A valid Plaid Link token is required.");
  }
  return createHash("sha256").update(token, "utf8").digest("hex");
}

function publicTokenHash(token) {
  if (typeof token !== "string" || !token.startsWith("public-") || token.length > 512) {
    throw new HTTPError(400, "A valid Plaid public token is required.");
  }
  return createHash("sha256").update(token, "utf8").digest("hex");
}

function hostedLinkExpiration(value) {
  const milliseconds = Date.parse(value);
  const now = Date.now();
  if (!Number.isFinite(milliseconds) || milliseconds <= now || milliseconds > now + (21 * 86_400_000)) {
    throw new HTTPError(502, "Plaid returned an invalid Hosted Link expiration.");
  }
  return {
    epochSeconds: Math.floor(milliseconds / 1000),
    isoString: new Date(milliseconds).toISOString()
  };
}

function validatedHostedLinkURL(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new HTTPError(502, "Plaid did not return a valid Hosted Link URL.");
  }
  if (url.protocol !== "https:" || (url.hostname !== "plaid.com" && !url.hostname.endsWith(".plaid.com"))) {
    throw new HTTPError(502, "Plaid did not return a trusted Hosted Link URL.");
  }
  return url.toString();
}

function isConnectionAttentionError(error) {
  return [
    "ITEM_LOGIN_REQUIRED",
    "PENDING_DISCONNECT",
    "USER_PERMISSION_REVOKED"
  ].includes(plaidErrorCode(error));
}

function isTemporarySyncError(error) {
  return [
    "PRODUCT_NOT_READY",
    "INSTITUTION_DOWN",
    "INSTITUTION_NOT_RESPONDING",
    "INSTITUTION_NO_LONGER_SUPPORTED"
  ].includes(plaidErrorCode(error));
}

export async function createLinkToken(userSub) {
  const [client, config] = await Promise.all([getPlaidClient(), getServerConfig()]);
  const response = await client.linkTokenCreate({
    user: { client_user_id: pseudonymousClientUserID(userSub) },
    client_name: "Orbit",
    products: [Products.Transactions],
    country_codes: [CountryCode.Us],
    language: "en",
    redirect_uri: config.redirectURI,
    webhook: config.webhookURL
  });
  return response.data.link_token;
}

export function buildHostedLinkRequest(userSub, config) {
  if (config.hostedLinkCompletionURI !== "orbit://finance") {
    throw new HTTPError(500, "HOSTED_LINK_COMPLETION_URI must be orbit://finance.");
  }
  return {
    user: { client_user_id: pseudonymousClientUserID(userSub) },
    client_name: "Orbit",
    products: [Products.Transactions],
    country_codes: [CountryCode.Us],
    language: "en",
    webhook: config.webhookURL,
    redirect_uri: config.redirectURI,
    hosted_link: {
      completion_redirect_uri: config.hostedLinkCompletionURI,
      is_mobile_app: true,
      url_lifetime_seconds: 1_800
    }
  };
}

export async function createHostedLink(userSub) {
  const [client, config] = await Promise.all([getPlaidClient(), getServerConfig()]);

  // Plaid requires both the allowlisted HTTPS OAuth redirect and the custom
  // completion callback whenever Hosted Link is marked as a mobile-app flow.
  const response = await client.linkTokenCreate(buildHostedLinkRequest(userSub, config));

  const linkToken = response.data.link_token;
  const hostedLinkURL = validatedHostedLinkURL(response.data.hosted_link_url);
  const expiration = hostedLinkExpiration(response.data.expiration);
  const connectionID = randomUUID();
  await saveHostedLinkSession({
    userSub,
    connectionID,
    linkTokenHash: hostedLinkTokenHash(linkToken),
    expiresAt: expiration.epochSeconds
  });

  return {
    hostedLinkURL,
    connectionID,
    expiresAt: expiration.isoString
  };
}

export async function getHostedLinkStatus(userSub, connectionID) {
  if (typeof connectionID !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(connectionID)) {
    throw new HTTPError(400, "A valid Hosted Link connection ID is required.");
  }

  const session = await getHostedLinkSessionForUser(userSub, connectionID);
  if (!session) throw new HTTPError(404, "That bank connection session was not found.");

  const terminal = ["complete", "exited", "failed", "expired"].includes(session.status);
  let status = session.status;
  if (!terminal && session.expiresAt <= Math.floor(Date.now() / 1000)) {
    status = "expired";
    await updateHostedLinkSession(session.linkTokenHash, status);
  }

  return {
    connectionID: session.connectionID,
    status,
    expiresAt: new Date(session.expiresAt * 1000).toISOString(),
    ...(session.completedAt ? { completedAt: session.completedAt } : {})
  };
}

async function refreshAccounts(client, userSub, item, accessToken) {
  const response = await client.accountsGet({ access_token: accessToken });
  const accounts = response.data.accounts.map(account => normalizeAccount(account, item));
  await saveAccounts(userSub, item, accounts);
}

async function syncTransactionsFromCursor(client, userSub, item, accessToken) {
  const originalCursor = item.cursor ?? null;
  let mutationRetries = 0;

  while (mutationRetries < 3) {
    let cursor = originalCursor;
    let pageCount = 0;
    try {
      do {
        const response = await client.transactionsSync({
          access_token: accessToken,
          cursor: cursor ?? undefined,
          count: 500
        });
        const data = response.data;
        await applyTransactionChanges(userSub, item.itemID, {
          added: data.added.map(transaction => normalizeTransaction(transaction)),
          modified: data.modified.map(transaction => normalizeTransaction(transaction)),
          removed: data.removed
        });
        cursor = data.next_cursor;
        pageCount += 1;
        if (pageCount > 100) throw new HTTPError(502, "Plaid returned too many transaction pages.");
        if (!data.has_more) break;
      } while (true);

      await updateItemSyncState(userSub, item.itemID, cursor);
      return;
    } catch (error) {
      if (plaidErrorCode(error) !== "TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION") throw error;
      mutationRetries += 1;
    }
  }
  throw new HTTPError(503, "Transactions changed while Orbit was syncing. Try refreshing again.");
}

export async function syncOneItem(userSub, item) {
  const client = await getPlaidClient();
  const accessToken = await decryptAccessToken(item.accessTokenCiphertext, userSub, item.itemID);
  await refreshAccounts(client, userSub, item, accessToken);
  await syncTransactionsFromCursor(client, userSub, item, accessToken);
}

async function exchangeAndSavePublicToken(userSub, publicToken) {
  if (typeof publicToken !== "string" || !publicToken.startsWith("public-") || publicToken.length > 512) {
    throw new HTTPError(400, "A valid Plaid public token is required.");
  }

  const client = await getPlaidClient();
  const exchange = await client.itemPublicTokenExchange({ public_token: publicToken });
  const accessToken = exchange.data.access_token;
  const itemID = exchange.data.item_id;
  const itemResponse = await client.itemGet({ access_token: accessToken });
  const institutionID = itemResponse.data.item.institution_id ?? null;
  // Avoid a second institution lookup in the webhook's response window. Plaid's
  // Item response normally includes this name; use a safe placeholder if not.
  const name = itemResponse.data.item.institution_name || "Financial institution";
  const accessTokenCiphertext = await encryptAccessToken(accessToken, userSub, itemID);
  const item = { itemID, institutionID, institutionName: name, accessTokenCiphertext };

  await savePlaidItem(userSub, item);
  const storedItem = await getUserItem(userSub, itemID);
  return { client, accessToken, storedItem };
}

export async function exchangePublicTokenWithoutSync(userSub, publicToken) {
  await exchangeAndSavePublicToken(userSub, publicToken);
}

export async function exchangePublicToken(userSub, publicToken) {
  const { client, accessToken, storedItem } = await exchangeAndSavePublicToken(userSub, publicToken);
  try {
    await refreshAccounts(client, userSub, storedItem, accessToken);
    await syncTransactionsFromCursor(client, userSub, storedItem, accessToken);
  } catch (error) {
    if (!isTemporarySyncError(error)) throw error;
  }
  return buildOverview(await listUserRecords(userSub));
}

export async function getOverview(userSub) {
  return buildOverview(await listUserRecords(userSub));
}

export async function syncAllItems(userSub) {
  const items = await listUserItems(userSub);
  for (const item of items) {
    try {
      await syncOneItem(userSub, item);
    } catch (error) {
      if (isConnectionAttentionError(error)) {
        await markItemNeedsAttention(userSub, item.itemID, true);
        continue;
      }
      if (isTemporarySyncError(error)) continue;
      console.error(JSON.stringify(safeErrorLog(error, "SYNC_ITEM")));
      throw error;
    }
  }
  return getOverview(userSub);
}

export async function disconnectItem(userSub, itemID) {
  if (typeof itemID !== "string" || itemID.length < 5 || itemID.length > 128) {
    throw new HTTPError(400, "A valid Plaid Item ID is required.");
  }
  const item = await getUserItem(userSub, itemID);
  if (!item) throw new HTTPError(404, "That financial connection was not found.");

  const client = await getPlaidClient();
  const accessToken = await decryptAccessToken(item.accessTokenCiphertext, userSub, itemID);
  try {
    await client.itemRemove({ access_token: accessToken });
  } catch (error) {
    if (!["ITEM_NOT_FOUND", "INVALID_ACCESS_TOKEN"].includes(plaidErrorCode(error))) throw error;
  }
  await deleteItemData(userSub, itemID);
}

function headerValue(headers, name) {
  const wanted = name.toLowerCase();
  for (const [key, value] of Object.entries(headers ?? {})) {
    if (key.toLowerCase() === wanted) return value;
  }
  return null;
}

export async function verifyWebhook(rawBody, headers) {
  const signedJWT = headerValue(headers, "Plaid-Verification");
  if (!signedJWT) throw new HTTPError(401, "Missing Plaid webhook signature.");

  let header;
  try {
    header = decodeProtectedHeader(signedJWT);
  } catch {
    throw new HTTPError(401, "Invalid Plaid webhook signature.");
  }
  if (header.alg !== "ES256" || typeof header.kid !== "string") {
    throw new HTTPError(401, "Invalid Plaid webhook signature.");
  }

  const client = await getPlaidClient();
  const response = await client.webhookVerificationKeyGet({ key_id: header.kid });
  const jwk = response.data.key;
  if (jwk.expired_at && jwk.expired_at < Math.floor(Date.now() / 1000)) {
    throw new HTTPError(401, "Expired Plaid webhook key.");
  }

  let verified;
  try {
    const key = await importJWK(jwk, "ES256");
    verified = await jwtVerify(signedJWT, key, { algorithms: ["ES256"] });
  } catch {
    throw new HTTPError(401, "Invalid Plaid webhook signature.");
  }
  const issuedAt = Number(verified.payload.iat);
  if (!Number.isFinite(issuedAt) || Math.abs(Date.now() / 1000 - issuedAt) > 300) {
    throw new HTTPError(401, "Expired Plaid webhook signature.");
  }

  const claimedHash = verified.payload.request_body_sha256;
  if (typeof claimedHash !== "string" || !/^[a-f0-9]{64}$/i.test(claimedHash)) {
    throw new HTTPError(401, "Invalid Plaid webhook body signature.");
  }
  const actual = Buffer.from(createHash("sha256").update(rawBody, "utf8").digest("hex"), "hex");
  const expected = Buffer.from(claimedHash, "hex");
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
    throw new HTTPError(401, "Invalid Plaid webhook body signature.");
  }
}

function hostedWebhookPublicTokens(webhook) {
  if (webhook.webhook_code === "ITEM_ADD_RESULT") {
    return typeof webhook.public_token === "string" ? [webhook.public_token] : [];
  }
  if (webhook.webhook_code !== "SESSION_FINISHED" || webhook.status !== "SUCCESS") return [];
  if (Array.isArray(webhook.public_tokens)) {
    return webhook.public_tokens.filter(token => typeof token === "string");
  }
  return webhook.public_token ? [webhook.public_token] : [];
}

async function handleHostedLinkWebhook(webhook) {
  if (webhook.webhook_type !== "LINK" ||
      !["ITEM_ADD_RESULT", "SESSION_FINISHED"].includes(webhook.webhook_code)) {
    return false;
  }
  if (typeof webhook.link_token !== "string") return true;

  let linkTokenHash;
  try {
    linkTokenHash = hostedLinkTokenHash(webhook.link_token);
  } catch {
    return true;
  }

  const session = await getHostedLinkSessionByTokenHash(linkTokenHash);
  if (!session || session.entityType !== "HOSTED_LINK_SESSION") return true;
  if (["complete", "exited", "expired"].includes(session.status)) return true;

  if (session.expiresAt <= Math.floor(Date.now() / 1000)) {
    await updateHostedLinkSession(linkTokenHash, "expired");
    return true;
  }

  const linkSessionID = typeof webhook.link_session_id === "string"
    ? webhook.link_session_id.slice(0, 128)
    : undefined;

  if (webhook.webhook_code === "SESSION_FINISHED" && webhook.status === "EXITED") {
    await updateHostedLinkSession(linkTokenHash, "exited", { linkSessionID });
    return true;
  }

  const tokens = hostedWebhookPublicTokens(webhook);
  if (tokens.length === 0 || tokens.length > 10) {
    if (webhook.webhook_code === "SESSION_FINISHED") {
      await updateHostedLinkSession(linkTokenHash, "failed", { linkSessionID });
    }
    return true;
  }

  let exchangedAny = false;
  for (const publicToken of tokens) {
    const tokenHash = publicTokenHash(publicToken);
    const claimed = await claimHostedPublicToken(session, tokenHash);
    if (!claimed) continue;

    await updateHostedLinkSession(linkTokenHash, "processing", { linkSessionID });
    try {
      // Keep Plaid's webhook fast: only exchange, encrypt, and persist the Item.
      // Orbit's authenticated refresh endpoint performs account/transaction sync.
      await exchangePublicTokenWithoutSync(session.userSub, publicToken);
      await completeHostedPublicToken(tokenHash);
      exchangedAny = true;
    } catch (error) {
      // A Plaid webhook retry can safely try again if exchange failed before the
      // one-time public token was consumed. No raw token is ever persisted.
      await releaseHostedPublicToken(tokenHash);
      await updateHostedLinkSession(linkTokenHash, "pending", {
        linkSessionID,
        lastAttemptFailedAt: new Date().toISOString()
      });
      throw error;
    }
  }

  if (exchangedAny) {
    await updateHostedLinkSession(linkTokenHash, "complete", {
      linkSessionID,
      completedAt: new Date().toISOString()
    });
  }
  return true;
}

export async function handlePlaidWebhook(rawBody, headers) {
  await verifyWebhook(rawBody, headers);
  let webhook;
  try {
    webhook = JSON.parse(rawBody);
  } catch {
    throw new HTTPError(400, "The webhook body must be JSON.");
  }

  const config = await getServerConfig();
  if (webhook.environment && webhook.environment !== config.environment) return;
  if (await handleHostedLinkWebhook(webhook)) return;
  if (typeof webhook.item_id !== "string") return;
  const owner = await findItemOwner(webhook.item_id);
  if (!owner) return;

  if (webhook.webhook_type === "TRANSACTIONS") {
    try {
      await syncOneItem(owner.userSub, owner);
    } catch (error) {
      if (isConnectionAttentionError(error)) {
        await markItemNeedsAttention(owner.userSub, owner.itemID, true);
        return;
      }
      if (isTemporarySyncError(error)) return;
      throw error;
    }
    return;
  }

  if (webhook.webhook_type === "ITEM") {
    const needsAttention = [
      "ERROR",
      "PENDING_EXPIRATION",
      "PENDING_DISCONNECT",
      "USER_PERMISSION_REVOKED"
    ].includes(webhook.webhook_code);
    if (needsAttention) await markItemNeedsAttention(owner.userSub, owner.itemID, true);
  }
}
