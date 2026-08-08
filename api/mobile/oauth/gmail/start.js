const { requireEnv, signState, providerCallback, validateMobileCallback, webRedirect } = require('../_shared');

module.exports = async function handler(req, res) {
  try {
    requireEnv(['GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'OAUTH_STATE_SECRET']);
    const callback = validateMobileCallback(req.query.callback);
    const state = signState({ provider: 'gmail', callback, createdAt: Date.now() });
    const url = new URL('https://accounts.google.com/o/oauth2/v2/auth');
    url.search = new URLSearchParams({
      client_id: process.env.GOOGLE_CLIENT_ID,
      redirect_uri: providerCallback(req, 'gmail'),
      response_type: 'code',
      scope: 'openid email https://www.googleapis.com/auth/gmail.readonly',
      access_type: 'offline',
      prompt: 'consent',
      include_granted_scopes: 'true',
      state
    }).toString();
    webRedirect(res, url.toString());
  } catch (error) {
    res.status(503).json({ error: error.message });
  }
};
