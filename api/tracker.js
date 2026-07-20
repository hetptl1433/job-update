const { get, put } = require('@vercel/blob');
const seed = [];

const pathname = 'interview-tracker/data.json';

function isConfigured() {
  return Boolean(
    process.env.BLOB_READ_WRITE_TOKEN ||
    (process.env.VERCEL_OIDC_TOKEN && process.env.BLOB_STORE_ID)
  );
}

function isAuthorized(req) {
  return req.headers['x-admin-password'] === process.env.ADMIN_PASSWORD;
}

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store, private');

  if (!process.env.ADMIN_PASSWORD) {
    return res.status(503).json({
      error: 'ADMIN_PASSWORD is not configured',
      locked: true,
    });
  }

  if (!isAuthorized(req)) {
    return res.status(401).json({ error: 'Admin password required', locked: true });
  }

  const configured = isConfigured();

  if (req.method === 'GET') {
    if (!configured) {
      return res.status(200).json({ data: seed, cloud: false, updatedAt: null });
    }

    try {
      const result = await get(pathname, {
        access: 'private',
        useCache: false,
      });

      if (!result || result.statusCode !== 200 || !result.stream) {
        return res.status(200).json({ data: seed, cloud: true, updatedAt: null });
      }

      const text = await new Response(result.stream).text();
      const data = JSON.parse(text);

      return res.status(200).json({
        data: Array.isArray(data) ? data : seed,
        cloud: true,
        updatedAt: result.blob.uploadedAt,
      });
    } catch (error) {
      return res.status(200).json({
        data: seed,
        cloud: false,
        updatedAt: null,
        warning: error.message,
      });
    }
  }

  if (req.method === 'PUT') {
    if (!configured) {
      return res.status(503).json({ error: 'Private Vercel Blob is not connected', cloud: false });
    }

    try {
      const data = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
      if (!Array.isArray(data)) {
        return res.status(400).json({ error: 'Invalid tracker data' });
      }

      const blob = await put(pathname, JSON.stringify(data, null, 2), {
        access: 'private',
        addRandomSuffix: false,
        allowOverwrite: true,
        contentType: 'application/json',
        cacheControlMaxAge: 60,
      });

      return res.status(200).json({
        ok: true,
        cloud: true,
        updatedAt: new Date().toISOString(),
        pathname: blob.pathname,
      });
    } catch (error) {
      return res.status(500).json({ error: error.message || 'Could not save tracker data' });
    }
  }

  res.setHeader('Allow', 'GET, PUT');
  return res.status(405).json({ error: 'Method not allowed' });
};
