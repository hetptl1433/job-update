const { requireEnv, verifyState, providerCallback, mobileRedirect, exchangeToken, saveConnection } = require('../_shared');

module.exports = async function handler(req, res) {
  let state;
  try {
    requireEnv(['LINKEDIN_CLIENT_ID', 'LINKEDIN_CLIENT_SECRET', 'OAUTH_STATE_SECRET']);
    state = verifyState(req.query.state);
    if (state.provider !== 'linkedin' || !req.query.code) throw new Error(req.query.error_description || req.query.error || 'LinkedIn did not return an authorization code');
    const tokens = await exchangeToken('https://www.linkedin.com/oauth/v2/accessToken', {
      grant_type: 'authorization_code',
      code: req.query.code,
      client_id: process.env.LINKEDIN_CLIENT_ID,
      client_secret: process.env.LINKEDIN_CLIENT_SECRET,
      redirect_uri: providerCallback(req, 'linkedin')
    });
    await saveConnection('linkedin', tokens);
    mobileRedirect(res, state.callback, 'linkedin', { connected: 1 });
  } catch (error) {
    if (state?.callback) return mobileRedirect(res, state.callback, 'linkedin', { connected: 0, error: error.message });
    res.status(400).json({ error: error.message });
  }
};
