const { requireEnv, signState, providerCallback, validateMobileCallback, webRedirect } = require('../_shared');

module.exports = async function handler(req, res) {
  try {
    requireEnv(['LINKEDIN_CLIENT_ID', 'LINKEDIN_CLIENT_SECRET', 'OAUTH_STATE_SECRET']);
    const callback = validateMobileCallback(req.query.callback);
    const state = signState({ provider: 'linkedin', callback, createdAt: Date.now() });
    const url = new URL('https://www.linkedin.com/oauth/v2/authorization');
    url.search = new URLSearchParams({
      response_type: 'code',
      client_id: process.env.LINKEDIN_CLIENT_ID,
      redirect_uri: providerCallback(req, 'linkedin'),
      scope: 'openid profile email',
      state
    }).toString();
    webRedirect(res, url.toString());
  } catch (error) {
    res.status(503).json({ error: error.message });
  }
};
