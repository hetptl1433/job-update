const { requireEnv, verifyState, providerCallback, mobileRedirect, exchangeToken, saveConnection } = require('../_shared');

module.exports = async function handler(req, res) {
  let state;
  try {
    requireEnv(['INDEED_CLIENT_ID', 'INDEED_CLIENT_SECRET', 'OAUTH_STATE_SECRET']);
    state = verifyState(req.query.state);
    if (state.provider !== 'indeed' || !req.query.code) throw new Error(req.query.error_description || req.query.error || 'Indeed did not return an authorization code');
    const tokens = await exchangeToken('https://apis.indeed.com/oauth/v2/tokens', {
      grant_type: 'authorization_code',
      code: req.query.code,
      redirect_uri: providerCallback(req, 'indeed')
    }, `${process.env.INDEED_CLIENT_ID}:${process.env.INDEED_CLIENT_SECRET}`);
    await saveConnection('indeed', tokens);
    mobileRedirect(res, state.callback, 'indeed', { connected: 1 });
  } catch (error) {
    if (state?.callback) return mobileRedirect(res, state.callback, 'indeed', { connected: 0, error: error.message });
    res.status(400).json({ error: error.message });
  }
};
