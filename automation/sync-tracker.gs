/**
 * Job Radar — daily tracker sync.
 *
 * Stage 2 of the pipeline. ChatGPT already read Gmail and mailed a digest; this
 * moves that digest into production. No LLM call and no API key — ChatGPT did
 * the judging, this is a parser and a writer.
 *
 * Order matters and follows the documented safe-update algorithm:
 *
 *   Gmail digest -> live cloud (PUT) -> both seed files (commit) -> verify
 *
 * The cloud write comes first because interview-tracker/data.json is what the
 * site actually serves. A seed-only change would be invisible in production:
 * api/tracker.js deliberately preserves the existing Blob record over a
 * duplicate seed record so manual phone edits are never clobbered.
 *
 * Setup lives in automation/README.md.
 */

const CONFIG = {
  sentinel: 'JOBRADAR_SYNC_V1',
  searchWindow: 'newer_than:3d',
  repo: 'hetptl1433/job-update',
  branch: 'main',
  // Overridden by the PRODUCTION_URL script property. Note that
  // job-update.vercel.app belongs to an unrelated project — the deployment for
  // this repo is job-update-hetptl1433s-projects.vercel.app. Confirm the
  // current alias in the Vercel dashboard before trusting either.
  production: 'https://job-update-hetptl1433s-projects.vercel.app',
  browserSeed: 'data/seed.js',
  apiSeed: 'api/tracker.js',
  // A digest rewriting more than this many records is treated as a bad parse
  // rather than a real day of recruiting news, and is refused.
  maxChanges: 8,
  deployTimeoutMs: 180000,
};

/** The only fields ever persisted. Anything else in a digest is dropped. */
const FIELDS = [
  'company', 'role', 'stage', 'inviteDate', 'interviewDate', 'status',
  'priority', 'nextAction', 'followUpDate', 'contact', 'mode', 'source', 'notes',
];

/** Matching keys. A digest never rewrites these on an existing record. */
const IDENTITY = ['company', 'role'];

/** Fields where an empty value means "unknown", not "clear this". */
const NEVER_BLANK = ['status', 'stage', 'priority'];

/** Entry point — point the daily trigger at this. */
function syncTracker() {
  const props = PropertiesService.getScriptProperties();
  const token = requireProperty_(props, 'GITHUB_TOKEN');
  const password = requireProperty_(props, 'ADMIN_PASSWORD');

  try {
    const outcome = runSync_(props, token, password);
    if (outcome.committed) report_('Job Radar synced', outcome.lines.join('\n'));
    log_(outcome.lines.join(' | '));
  } catch (error) {
    report_('Job Radar sync FAILED', String(error && error.stack || error));
    throw error;
  }
}

function runSync_(props, token, password) {
  const lines = [];

  const digest = findLatestDigest_();
  if (!digest) return done_(lines, 'No digest found in the last ' + CONFIG.searchWindow + '.');
  if (digest.messageId === props.getProperty('LAST_MESSAGE_ID')) {
    return done_(lines, 'Digest ' + digest.messageId + ' was already applied.');
  }

  const changes = validateChanges_(extractPayload_(digest.body)).map(scrubChange_);
  if (!changes.length) {
    props.setProperty('LAST_MESSAGE_ID', digest.messageId);
    return done_(lines, 'Digest parsed cleanly and reported no changes.');
  }
  lines.push('Digest from ' + digest.date + ' carried ' + changes.length + ' change(s).');

  // 1. Read live cloud data. This is the authoritative dataset — it holds
  //    manual phone edits that exist nowhere else.
  const live = fetchCloud_(password);
  if (!live.cloud) {
    throw new Error('Refusing to sync: the API reports cloud storage is unavailable, so a PUT would not persist.');
  }
  lines.push('Read ' + live.data.length + ' live record(s) from the cloud tracker.');

  // 2. Reconcile. Only fields the digest verified are touched; everything else
  //    on the record survives untouched.
  const result = applyChanges_(live.data, changes);
  if (!result.updated && !result.added) {
    props.setProperty('LAST_MESSAGE_ID', digest.messageId);
    return done_(lines, 'Digest changes already matched production. Nothing to write.');
  }
  if (result.records.length < live.data.length) {
    throw new Error('Refusing to sync: reconciliation lost records.');
  }
  lines.push('Reconciled: ' + result.updated + ' updated, ' + result.added + ' added.');

  // 3. Write the cloud first, so production is correct even if GitHub fails.
  putCloud_(password, result.records);
  lines.push('Wrote reconciled dataset to interview-tracker/data.json.');

  // 4. Mirror into both seed copies so the fallback path stays accurate.
  const sha = commitSeeds_(token, result.records, buildCommitMessage_(result));
  lines.push('Committed both seed files as ' + sha.slice(0, 7) + '.');

  // 5. Verify rather than assume.
  const verified = verifyProduction_(password, changes);
  lines.push(verified.ok
    ? 'Verified production returns every change.'
    : 'WARNING — production did not reflect: ' + verified.missing.join(', '));

  const deploy = checkDeployment_(token, sha);
  lines.push('Vercel deployment: ' + deploy);

  props.setProperty('LAST_MESSAGE_ID', digest.messageId);
  props.setProperty('LAST_RUN', new Date().toISOString());
  return { committed: true, lines: lines };
}

function done_(lines, message) {
  lines.push(message);
  return { committed: false, lines: lines };
}

function requireProperty_(props, name) {
  const value = props.getProperty(name);
  if (!value) throw new Error(name + ' script property is not set');
  return value;
}

/* -------------------------------------------------------------- Gmail --- */

/**
 * Finds the digest by its sentinel rather than by sender, so it keeps working
 * whether ChatGPT mails you directly or OpenAI sends the task notification.
 */
function findLatestDigest_() {
  const threads = GmailApp.search('"' + CONFIG.sentinel + '" ' + CONFIG.searchWindow, 0, 10);
  let newest = null;

  for (const thread of threads) {
    for (const message of thread.getMessages()) {
      const body = message.getPlainBody();
      if (body.indexOf(CONFIG.sentinel) === -1) continue;
      if (newest && message.getDate() <= newest.date) continue;
      newest = { messageId: message.getId(), date: message.getDate(), body: body };
    }
  }
  return newest;
}

function extractPayload_(body) {
  const fenced = body.match(/```(?:json)?\s*([\s\S]*?)```/);
  const candidate = fenced ? fenced[1] : sliceBraces_(body);
  if (!candidate) throw new Error('No JSON block found in the digest');

  let parsed;
  try {
    parsed = JSON.parse(candidate.trim());
  } catch (error) {
    throw new Error('Digest JSON did not parse: ' + error.message);
  }
  if (parsed.schema !== CONFIG.sentinel) throw new Error('Unexpected schema: ' + parsed.schema);
  return parsed;
}

function sliceBraces_(body) {
  const start = body.indexOf('{');
  const end = body.lastIndexOf('}');
  return start === -1 || end <= start ? null : body.slice(start, end + 1);
}

function validateChanges_(payload) {
  const changes = Array.isArray(payload.changes) ? payload.changes : [];
  if (changes.length > CONFIG.maxChanges) {
    throw new Error('Digest reported ' + changes.length + ' changes, over the limit of ' + CONFIG.maxChanges);
  }
  for (const change of changes) {
    if (!change || !String(change.company || '').trim() || !String(change.role || '').trim()) {
      throw new Error('Every change needs a company and a role');
    }
  }
  return changes;
}

/**
 * Enforces the privacy rules on the way in rather than trusting the digest:
 * no Gmail links, message ids, addresses, or tokens ever reach the repo.
 */
function scrubChange_(change) {
  const clean = {};
  FIELDS.forEach((field) => {
    if (change[field] === undefined) return;
    clean[field] = scrubText_(String(change[field]));
  });
  return clean;
}

function scrubText_(value) {
  return value
    .replace(/https?:\/\/\S+/gi, '')
    .replace(/[\w.+-]+@[\w-]+\.[\w.]+/g, 'recruiting contact')
    .replace(/\b[A-Za-z0-9_-]{24,}\b/g, '')
    .replace(/\s{2,}/g, ' ')
    .trim()
    .slice(0, 400);
}

/* ------------------------------------------------------- Reconciliation --- */

function normalizeKey_(value) {
  return String(value || '').trim().toLowerCase();
}

/** Mirrors api/tracker.js exactly so both sides agree on identity. */
function recordKeys_(item) {
  const keys = [];
  if (item && item.id !== undefined && item.id !== null && item.id !== '') {
    keys.push('id:' + item.id);
  }
  const company = normalizeKey_(item && item.company);
  const role = normalizeKey_(item && item.role);
  if (company || role) keys.push('job:' + company + '|' + role);
  return keys;
}

/** Secondary key: "Formlabs Inc." and "Formlabs" are the same company. */
function loosePart_(value) {
  return normalizeKey_(value)
    .replace(/[.,]/g, '')
    .replace(/\b(inc|llc|ltd|corp|corporation|co|gmbh|plc|limited|technologies|electronics)\b/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function looseKey_(item) {
  return 'loose:' + loosePart_(item && item.company) + '|' + loosePart_(item && item.role);
}

/**
 * Applies verified fields onto matching records and appends genuinely new ones.
 * Records are never deleted — a dropped record is indistinguishable from a
 * parse failure, and the cloud dataset is the only copy of manual edits.
 */
function applyChanges_(records, changes) {
  const merged = records.map((item) => Object.assign({}, item));
  const index = {};
  merged.forEach((item, position) => {
    recordKeys_(item).forEach((key) => { if (index[key] === undefined) index[key] = position; });
    const loose = looseKey_(item);
    if (index[loose] === undefined) index[loose] = position;
  });

  const touched = [];
  let updated = 0;
  let added = 0;

  for (const change of changes) {
    let position = -1;
    const candidates = recordKeys_(change).concat([looseKey_(change)]);
    for (const key of candidates) {
      if (index[key] !== undefined) { position = index[key]; break; }
    }

    if (position === -1) {
      const record = { id: nextId_(merged) };
      FIELDS.forEach((field) => { record[field] = String(change[field] || ''); });
      if (!record.status) record.status = 'Need Status Update';
      if (!record.priority) record.priority = 'Medium';
      if (!record.stage) record.stage = 'Unknown';
      merged.push(record);
      recordKeys_(record).forEach((key) => { index[key] = merged.length - 1; });
      index[looseKey_(record)] = merged.length - 1;
      touched.push(record.company);
      added++;
      continue;
    }

    const current = merged[position];
    const next = Object.assign({}, current);
    let changed = false;

    FIELDS.forEach((field) => {
      if (change[field] === undefined) return;
      // Identity is for matching only. Rewriting it would orphan the record.
      if (IDENTITY.indexOf(field) !== -1) return;
      const value = String(change[field]);
      if (!value && NEVER_BLANK.indexOf(field) !== -1) return;
      if (value === String(current[field] === undefined ? '' : current[field])) return;
      next[field] = value;
      changed = true;
    });

    if (changed) {
      merged[position] = next;
      touched.push(next.company);
      updated++;
    }
  }

  return { records: merged, updated: updated, added: added, touched: touched };
}

function nextId_(records) {
  return records.reduce((max, item) => Math.max(max, Number(item.id) || 0), 1000) + 1;
}

function buildCommitMessage_(result) {
  const names = result.touched.filter((name, position, all) => all.indexOf(name) === position);
  const summary = names.slice(0, 3).join(', ') + (names.length > 3 ? ' and more' : '');
  return 'Sync tracker from verified recruiting digest (' + summary + ')';
}

/* ------------------------------------------------------ Tracker API --- */

/** Base URL, overridable without editing this file. */
function productionUrl_() {
  const override = PropertiesService.getScriptProperties().getProperty('PRODUCTION_URL');
  return String(override || CONFIG.production).replace(/\/+$/, '');
}

function trackerFetch_(password, options) {
  const props = PropertiesService.getScriptProperties();
  const headers = { 'x-admin-password': password };

  // Vercel Deployment Protection sits in front of the whole deployment and is
  // separate from ADMIN_PASSWORD. Without a bypass token it answers every
  // request with an SSO redirect, so the API is never reached at all.
  const bypass = props.getProperty('VERCEL_BYPASS');
  if (bypass) headers['x-vercel-protection-bypass'] = bypass;

  const url = productionUrl_() + '/api/tracker';
  const response = UrlFetchApp.fetch(url, Object.assign({
    method: 'get',
    muteHttpExceptions: true,
    followRedirects: false,
    headers: headers,
  }, options || {}));

  const code = response.getResponseCode();
  const text = response.getContentText();

  if (code === 302 || code === 307) {
    const target = String(response.getHeaders().Location || '');
    if (target.indexOf('sso-api') !== -1 || target.indexOf('vercel.com/sso') !== -1) {
      throw new Error(
        'Vercel Deployment Protection is blocking ' + url + '. Either disable ' +
        'protection for production, or create a Protection Bypass for Automation ' +
        'secret in Vercel and store it as the VERCEL_BYPASS script property.');
    }
    throw new Error('Unexpected redirect from ' + url + ' to ' + target);
  }

  if (code === 401) throw new Error('ADMIN_PASSWORD rejected by ' + url);
  if (code < 200 || code >= 300) {
    throw new Error(url + ' returned ' + code + ': ' + text.slice(0, 300));
  }

  // A wrong PRODUCTION_URL usually still returns 200 — with someone else's
  // index.html. Fail loudly rather than letting JSON.parse report a syntax error.
  if (text.slice(0, 200).trim().toLowerCase().indexOf('<!doctype') === 0) {
    throw new Error(
      url + ' returned HTML instead of JSON. PRODUCTION_URL is probably pointing ' +
      'at the wrong deployment — job-update.vercel.app belongs to a different project.');
  }

  try {
    return JSON.parse(text);
  } catch (error) {
    throw new Error('Could not parse the response from ' + url + ': ' + text.slice(0, 200));
  }
}

function fetchCloud_(password) {
  const payload = trackerFetch_(password);
  return { data: Array.isArray(payload.data) ? payload.data : [], cloud: Boolean(payload.cloud) };
}

function putCloud_(password, records) {
  const payload = trackerFetch_(password, {
    method: 'put',
    contentType: 'application/json',
    payload: JSON.stringify(records),
  });
  if (!payload.ok) throw new Error('Cloud write did not confirm: ' + JSON.stringify(payload).slice(0, 200));
  return payload;
}

/** Reads production back and confirms each change actually landed. */
function verifyProduction_(password, changes) {
  const live = fetchCloud_(password);
  const missing = [];

  for (const change of changes) {
    const match = live.data.filter((item) => {
      const keys = recordKeys_(item).concat([looseKey_(item)]);
      return recordKeys_(change).concat([looseKey_(change)]).some((key) => keys.indexOf(key) !== -1);
    })[0];

    if (!match) { missing.push(change.company + ' (absent)'); continue; }
    if (change.status && String(match.status) !== String(change.status)) {
      missing.push(change.company + ' (status ' + match.status + ')');
    }
  }
  return { ok: missing.length === 0, missing: missing };
}

/* ----------------------------------------------------------- GitHub --- */

function githubFetch_(token, path, options) {
  const response = UrlFetchApp.fetch('https://api.github.com' + path, Object.assign({
    method: 'get',
    muteHttpExceptions: true,
    headers: {
      Authorization: 'Bearer ' + token,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  }, options || {}));

  const code = response.getResponseCode();
  const text = response.getContentText();
  if (code < 200 || code >= 300) {
    throw new Error('GitHub ' + path + ' returned ' + code + ': ' + text.slice(0, 300));
  }
  return JSON.parse(text);
}

function readFile_(token, path) {
  const data = githubFetch_(token, '/repos/' + CONFIG.repo + '/contents/' + path + '?ref=' + CONFIG.branch);
  return Utilities.newBlob(Utilities.base64Decode(data.content)).getDataAsString();
}

/** Writes both seed copies in a single commit so they can never drift apart. */
function commitSeeds_(token, records, message) {
  const apiSource = readFile_(token, CONFIG.apiSeed);
  const json = JSON.stringify(records);

  return commitFiles_(token, [
    { path: CONFIG.browserSeed, content: 'window.SEED_DATA = ' + json + ';\n' },
    { path: CONFIG.apiSeed, content: replaceSeedArray_(apiSource, 'const seed = ', json) },
  ], message);
}

function replaceSeedArray_(source, marker, json) {
  const start = source.indexOf(marker);
  if (start === -1) throw new Error('Could not find "' + marker + '" in api/tracker.js');
  const arrayStart = source.indexOf('[', start);
  const arrayEnd = source.indexOf('];', arrayStart);
  if (arrayStart === -1 || arrayEnd === -1) throw new Error('Could not locate the seed array bounds');
  return source.slice(0, arrayStart) + json + source.slice(arrayEnd + 1);
}

function commitFiles_(token, files, message) {
  const repo = '/repos/' + CONFIG.repo;
  const ref = githubFetch_(token, repo + '/git/ref/heads/' + CONFIG.branch);
  const head = githubFetch_(token, repo + '/git/commits/' + ref.object.sha);

  const tree = files.map((file) => {
    const blob = githubFetch_(token, repo + '/git/blobs', {
      method: 'post',
      contentType: 'application/json',
      payload: JSON.stringify({ content: file.content, encoding: 'utf-8' }),
    });
    return { path: file.path, mode: '100644', type: 'blob', sha: blob.sha };
  });

  const newTree = githubFetch_(token, repo + '/git/trees', {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify({ base_tree: head.tree.sha, tree: tree }),
  });

  const commit = githubFetch_(token, repo + '/git/commits', {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify({ message: message, tree: newTree.sha, parents: [ref.object.sha] }),
  });

  githubFetch_(token, repo + '/git/refs/heads/' + CONFIG.branch, {
    method: 'patch',
    contentType: 'application/json',
    payload: JSON.stringify({ sha: commit.sha }),
  });

  return commit.sha;
}

/** Polls the commit status so the run never claims a deploy it did not see. */
function checkDeployment_(token, sha) {
  const deadline = Date.now() + CONFIG.deployTimeoutMs;

  while (Date.now() < deadline) {
    const status = githubFetch_(token, '/repos/' + CONFIG.repo + '/commits/' + sha + '/status');
    if (status.state === 'success') return 'success';
    if (status.state === 'failure' || status.state === 'error') return status.state.toUpperCase();
    Utilities.sleep(15000);
  }
  return 'still pending after ' + (CONFIG.deployTimeoutMs / 1000) + 's — check Vercel';
}

/* ---------------------------------------------------------- Plumbing --- */

function report_(subject, body) {
  MailApp.sendEmail(Session.getEffectiveUser().getEmail(), subject, body);
}

function log_(message) {
  console.log('[job-radar] ' + message);
}

/** Run once by hand to install the daily trigger. */
function installTrigger() {
  ScriptApp.getProjectTriggers()
    .filter((trigger) => trigger.getHandlerFunction() === 'syncTracker')
    .forEach((trigger) => ScriptApp.deleteTrigger(trigger));

  ScriptApp.newTrigger('syncTracker').timeBased().atHour(7).everyDays(1).create();
  log_('Daily trigger installed for ~7am.');
}

/**
 * Run this FIRST. Confirms the script can actually reach the tracker API before
 * you worry about digests, and names the specific failure if it cannot.
 */
function checkConnection() {
  const props = PropertiesService.getScriptProperties();
  log_('Production URL: ' + productionUrl_());
  log_('VERCEL_BYPASS set: ' + (props.getProperty('VERCEL_BYPASS') ? 'yes' : 'no'));

  const password = requireProperty_(props, 'ADMIN_PASSWORD');
  const live = fetchCloud_(password);
  log_('OK — API reachable, ' + live.data.length + ' record(s), cloud=' + live.cloud);
  if (!live.cloud) log_('WARNING: cloud storage is not connected, so writes would not persist.');

  const token = requireProperty_(props, 'GITHUB_TOKEN');
  const ref = githubFetch_(token, '/repos/' + CONFIG.repo + '/git/ref/heads/' + CONFIG.branch);
  log_('OK — GitHub reachable, ' + CONFIG.branch + ' is at ' + ref.object.sha.slice(0, 7));
}

/** Run by hand to check parsing and matching without writing anything. */
function dryRun() {
  const password = requireProperty_(PropertiesService.getScriptProperties(), 'ADMIN_PASSWORD');
  const digest = findLatestDigest_();
  if (!digest) { log_('No digest found.'); return; }

  const changes = validateChanges_(extractPayload_(digest.body)).map(scrubChange_);
  const live = fetchCloud_(password);
  const result = applyChanges_(live.data, changes);

  log_('Digest from ' + digest.date + ' carries ' + changes.length + ' change(s).');
  log_('Would update ' + result.updated + ' and add ' + result.added + '. Nothing was written.');
  result.touched.forEach((name) => log_('  touched: ' + name));
}
