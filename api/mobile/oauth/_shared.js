const crypto = require('crypto');
const { put } = require('@vercel/blob');

function requireEnv(names) {
  const missing = names.filter((name) => !process.env[name]);
  if (missing.length) throw new Error(`Missing environment variables: ${missing.join(', ')}`);
}
function base64url(input) { return Buffer.from(input).toString('base64url'); }
function signState(payload) {
  requireEnv(['OAUTH_STATE_SECRET']);
  const body = base64url(JSON.stringify(payload));
  const signature = crypto.createHmac('sha256', process.env.OAUTH_STATE_SECRET).update(body).digest('base64url');
  return `${body}.${signature}`;
}
function verifyState(value) {
  requireEnv(['OAUTH_STATE_SECRET']);
  const [body, supplied] = String(value || '').split('.');
  if (!body || !supplied) throw new Error('Invalid OAuth state');
  const expected = crypto.createHmac('sha256', process.env.OAUTH_STATE_SECRET).update(body).digest('base64url');
  const left = Buffer.from(supplied);
  const right = Buffer.from(expected);
  if (left.length !== right.length || !crypto.timingSafeEqual(left, right)) throw new Error('OAuth state verification failed');
  const payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
  if (!payload.createdAt || Date.now() - payload.createdAt > 10 * 60 * 1000) throw new Error('OAuth state expired');
  return payload;
}
function publicBase(req) {
  const protocol = String(req.headers['x-forwarded-proto'] || 'https').split(',')[0];
  return `${protocol}://${req.headers.host}`;
}
function providerCallback(req, provider) { return `${publicBase(req)}/api/mobile/oauth/${provider}/callback`; }
function validateMobileCallback(value) {
  const parsed = new URL(String(value || 'jobradar://oauth'));
  if (parsed.protocol !== 'jobradar:') throw new Error('Unsupported mobile callback');
  return parsed.toString();
}
function mobileRedirect(res, callback, provider, values = {}) {
  const url = new URL(callback);
  url.pathname = `/${provider}`;
  for (const [key, value] of Object.entries(values)) url.searchParams.set(key, String(value));
  res.statusCode = 302;
  res.setHeader('Location', url.toString());
  res.end();
}
function webRedirect(res, url) {
  res.statusCode = 302;
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Location', url);
  res.end();
}
async function exchangeToken(url, body, basicCredentials) {
  const headers = { Accept: 'application/json', 'Content-Type': 'application/x-www-form-urlencoded' };
  if (basicCredentials) headers.Authorization = `Basic ${Buffer.from(basicCredentials).toString('base64')}`;
  const response = await fetch(url, { method: 'POST', headers, body: new URLSearchParams(body) });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error_description || data.error || `Token exchange failed (${response.status})`);
  return data;
}
async function saveConnection(provider, tokenData) {
  const safe = {
    provider,
    access_token: tokenData.access_token,
    refresh_token: tokenData.refresh_token,
    id_token: tokenData.id_token,
    scope: tokenData.scope,
    token_type: tokenData.token_type,
    expires_at: tokenData.expires_in ? Date.now() + Number(tokenData.expires_in) * 1000 : null,
    connected_at: new Date().toISOString()
  };
  await put(`interview-tracker/oauth/${provider}.json`, JSON.stringify(safe), {
    access: 'private', addRandomSuffix: false, allowOverwrite: true,
    contentType: 'application/json', cacheControlMaxAge: 60
  });
}
module.exports = { requireEnv, signState, verifyState, providerCallback, validateMobileCallback, mobileRedirect, webRedirect, exchangeToken, saveConnection };
