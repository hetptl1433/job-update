const { get, put } = require('@vercel/blob');
const pathname = 'interview-tracker/ios-devices.json';

function authorized(req) {
  return Boolean(process.env.ADMIN_PASSWORD) && req.headers['x-admin-password'] === process.env.ADMIN_PASSWORD;
}
async function readDevices() {
  try {
    const result = await get(pathname, { access: 'private', useCache: false });
    if (!result?.stream) return [];
    const parsed = JSON.parse(await new Response(result.stream).text());
    return Array.isArray(parsed) ? parsed : [];
  } catch { return []; }
}
module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store, private');
  if (!authorized(req)) return res.status(401).json({ error: 'Admin password required' });
  if (req.method === 'GET') return res.status(200).json({ count: (await readDevices()).length });
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
  const token = String(body?.token || '').toLowerCase();
  if (!/^[a-f0-9]{64,200}$/.test(token)) return res.status(400).json({ error: 'Invalid APNs device token' });
  const devices = await readDevices();
  const filtered = devices.filter((device) => device.token !== token);
  filtered.push({ token, platform: 'ios', updatedAt: new Date().toISOString() });
  await put(pathname, JSON.stringify(filtered, null, 2), {
    access: 'private', addRandomSuffix: false, allowOverwrite: true,
    contentType: 'application/json', cacheControlMaxAge: 60
  });
  return res.status(200).json({ ok: true, count: filtered.length });
};
