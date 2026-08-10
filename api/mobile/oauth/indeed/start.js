const { requireEnv, signState, providerCallback, validateMobileCallback, webRedirect } = require('../_shared');

module.exports = async function handler(req, res) {
  try {
    requireEnv(['INDEED_CLIENT_ID', 'INDEED_CLIENT_SECRET', 'OAUTH_STATE_SECRET']);
    const callback = validateMobileCallback(req.query.callback);
    const state = signState({ provider: 'indeed', callback, createdAt: Date.now() });
    const url = new URL('https://secure.indeed.com/oauth/v2/authorize');
    url.search = new URLSearchParams({
      response_type: 'code',
      client_id: process.env.INDEED_CLIENT_ID,
      redirect_uri: providerCallback(req, 'indeed'),
      scope: 'email offline_access',
      state
    }).toString();
    webRedirect(res, url.toString());
  } catch (error) {
    res.status(503).json({ error: error.message });
  }
};
