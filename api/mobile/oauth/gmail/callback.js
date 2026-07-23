const { requireEnv, verifyState, providerCallback, mobileRedirect, exchangeToken, saveConnection } = require('../_shared');

module.exports = async function handler(req, res) {
  let state;
  try {
    requireEnv(['GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'OAUTH_STATE_SECRET']);
    state = verifyState(req.query.state);
    if (state.provider !== 'gmail' || !req.query.code) throw new Error(req.query.error || 'Google did not return an authorization code');
    const tokens = await exchangeToken('https://oauth2.googleapis.com/token', {
      client_id: process.env.GOOGLE_CLIENT_ID,
      client_secret: process.env.GOOGLE_CLIENT_SECRET,
      code: req.query.code,
      grant_type: 'authorization_code',
      redirect_uri: providerCallback(req, 'gmail')
    });
    await saveConnection('gmail', tokens);
    mobileRedirect(res, state.callback, 'gmail', { connected: 1 });
  } catch (error) {
    if (state?.callback) return mobileRedirect(res, state.callback, 'gmail', { connected: 0, error: error.message });
    res.status(400).json({ error: error.message });
  }
};
