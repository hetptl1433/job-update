const crypto = require('crypto');
const http2 = require('http2');
const { get } = require('@vercel/blob');

function authorized(req) {
  return Boolean(process.env.ADMIN_PASSWORD) && req.headers['x-admin-password'] === process.env.ADMIN_PASSWORD;
}
function b64(value) { return Buffer.from(value).toString('base64url'); }
function providerToken() {
  const header = b64(JSON.stringify({ alg: 'ES256', kid: process.env.APNS_KEY_ID }));
  const payload = b64(JSON.stringify({ iss: process.env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) }));
  const unsigned = `${header}.${payload}`;
  const signature = crypto.sign('sha256', Buffer.from(unsigned), {
    key: process.env.APNS_PRIVATE_KEY.replace(/\\n/g, '\n'),
    dsaEncoding: 'ieee-p1363'
  }).toString('base64url');
  return `${unsigned}.${signature}`;
}
async function devices() {
  const result = await get('interview-tracker/ios-devices.json', { access: 'private', useCache: false });
  if (!result?.stream) return [];
  const parsed = JSON.parse(await new Response(result.stream).text());
  return Array.isArray(parsed) ? parsed : [];
}
function sendOne(client, token, auth, payload) {
  return new Promise((resolve) => {
    const request = client.request({
      ':method': 'POST', ':path': `/3/device/${token}`,
      authorization: `bearer ${auth}`,
      'apns-topic': process.env.APNS_BUNDLE_ID,
      'apns-push-type': 'alert', 'apns-priority': '10',
      'content-type': 'application/json'
    });
    let response = '';
    request.setEncoding('utf8');
    request.on('data', (chunk) => { response += chunk; });
    request.on('response', (headers) => resolve({ status: headers[':status'], response }));
    request.on('error', (error) => resolve({ status: 0, response: error.message }));
    request.end(JSON.stringify(payload));
  });
}
module.exports = async function handler(req, res) {
  if (!authorized(req)) return res.status(401).json({ error: 'Admin password required' });
  for (const name of ['APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_PRIVATE_KEY', 'APNS_BUNDLE_ID']) {
    if (!process.env[name]) return res.status(503).json({ error: `${name} is not configured` });
  }
  const body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body || {});
  const payload = {
    aps: {
      alert: {
        title: body.title || 'Job Radar updated',
        body: body.body || 'A verified application status changed.'
      },
      sound: 'default', badge: 1
    },
    applicationID: body.applicationID || null
  };
  const host = process.env.APNS_ENVIRONMENT === 'production'
    ? 'https://api.push.apple.com'
    : 'https://api.sandbox.push.apple.com';
  const client = http2.connect(host);
  const auth = providerToken();
  const list = await devices();
  const results = [];
  for (const device of list) results.push(await sendOne(client, device.token, auth, payload));
  client.close();
  res.status(200).json({ ok: true, attempted: list.length, results });
};
