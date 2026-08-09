const { get, put } = require('@vercel/blob');

const seed = [{"id":1001,"company":"Western Digital","role":"Fall 2026 Intern - IT Wafer Systems Automation","stage":"Recruiter Screen","inviteDate":"2026-07-15","interviewDate":"","status":"Need Status Update","priority":"High","nextAction":"Wait for the recruiter to confirm an interview time; follow up again if there is no reply.","followUpDate":"2026-07-23","contact":"Western Digital recruiting","mode":"TBD","source":"","notes":"Interview availability requested by email. Availability was sent July 15 and a follow-up was sent July 21."},{"id":1002,"company":"SNAP Life Sciences","role":"Internship Opportunity","stage":"Offer / Onboarding","inviteDate":"2026-07-06","interviewDate":"2026-07-06","status":"Offer Received","priority":"High","nextAction":"Review the offer letter and internship agreement and confirm acceptance/start details.","followUpDate":"2026-07-22","contact":"SNAP Life Sciences recruiting","mode":"Microsoft Teams","source":"","notes":"Teams interview invitation received July 6. Offer letter and internship agreement received July 8."},{"id":1003,"company":"Dometic","role":"Quality Engineering Intern","stage":"Offer / Onboarding","inviteDate":"2026-04-30","interviewDate":"2026-05-01","status":"Offer Accepted / Active","priority":"High","nextAction":"Continue the active internship and keep major milestones documented.","followUpDate":"","contact":"Dometic recruiting","mode":"Teams / Elkhart, IN","source":"","notes":"Interview, offer, pre-boarding, orientation, and active start were verified from recruiting emails."},{"id":1004,"company":"Experian","role":"AI SWE Summer Intern (Remote & Paid)","stage":"One-way Video","inviteDate":"2026-03-23","interviewDate":"2026-03-23","status":"Rejected","priority":"Medium","nextAction":"Closed.","followUpDate":"","contact":"Experian hiring team","mode":"Online video interview","source":"","notes":"Assessment and video interview invitation received; rejection update received April 28."},{"id":1005,"company":"Experian","role":"ML Engineer Summer Intern (Remote & Paid)","stage":"One-way Video","inviteDate":"2026-04-22","interviewDate":"2026-04-22","status":"Rejected","priority":"Medium","nextAction":"Closed.","followUpDate":"","contact":"Experian hiring team","mode":"Online video interview","source":"","notes":"Assessment and video interview invitation received; rejection update received May 7."},{"id":1006,"company":"MMI","role":"Full-stack Web Developer Intern","stage":"Hiring Manager Interview","inviteDate":"2026-04-27","interviewDate":"2026-04-28","status":"Need Status Update","priority":"High","nextAction":"Send a final status follow-up or close as no response if the role is no longer active.","followUpDate":"2026-07-22","contact":"MMI recruiting","mode":"Google Meet","source":"","notes":"Interview completed April 28. A follow-up was sent May 16, with no later decision found in Gmail."},{"id":1007,"company":"Lavner Education","role":"STEM Instructor / Intern","stage":"One-way Video","inviteDate":"2026-04-21","interviewDate":"2026-04-21","status":"Rejected","priority":"Low","nextAction":"Closed.","followUpDate":"","contact":"Lavner Education recruiting","mode":"Online interview","source":"","notes":"Interview invitation received April 21. Position update indicating non-selection received April 23."},{"id":1008,"company":"Lavner Education","role":"Instructor / Intern - Summer Camps","stage":"Final Interview","inviteDate":"2026-04-25","interviewDate":"2026-04-27","status":"Need Status Update","priority":"Medium","nextAction":"Confirm the outcome of the final interview and the later May 6 interview invitation.","followUpDate":"2026-07-22","contact":"Lavner Education recruiting","mode":"Online interview","source":"","notes":"Initial interview invitation received April 25, final interview invitation April 27, and another interview invitation May 6. No later decision was found."},{"id":1009,"company":"APR Consulting","role":"Embedded Software Engineer with Active Secret Clearance","stage":"Recruiter Screen","inviteDate":"2026-07-01","interviewDate":"","status":"Need Status Update","priority":"Medium","nextAction":"Confirm whether the virtual recruiter voice screening was completed and request the current status.","followUpDate":"2026-07-22","contact":"APR Consulting recruiting","mode":"Virtual voice screening","source":"","notes":"Voice-screening invitation received July 1 and reminder received July 2."},{"id":1010,"company":"Amazon","role":"Jr. Software Development Engineer - Jr. Developer Program","stage":"Technical Assessment","inviteDate":"2026-03-19","interviewDate":"2026-03-22","status":"Need Status Update","priority":"Medium","nextAction":"Check the Amazon Jobs portal for the assessment outcome and current application state.","followUpDate":"2026-07-22","contact":"Amazon Jobs","mode":"Online assessment","source":"","notes":"Assessment invitation received March 19 and completion confirmation received March 22. No later decision was found for this specific application."},{"id":1011,"company":"Citadel / Citadel Securities","role":"Software Engineering Campus Assessment 2025-2026","stage":"Technical Assessment","inviteDate":"2026-01-09","interviewDate":"","status":"Need Status Update","priority":"Low","nextAction":"Check whether the HackerRank assessment was completed and close or update the application accordingly.","followUpDate":"2026-07-22","contact":"Citadel hiring team","mode":"HackerRank","source":"","notes":"HackerRank assessment invitation verified from Gmail. No later status email was found."},{"id":1012,"company":"Interactive Brokers","role":"Behavioral Assessment","stage":"Technical Assessment","inviteDate":"2026-01-05","interviewDate":"","status":"Need Status Update","priority":"Low","nextAction":"Confirm whether the Predictive Index assessment was completed and update the application status.","followUpDate":"2026-07-22","contact":"Interactive Brokers recruiting","mode":"Predictive Index assessment","source":"","notes":"Behavioral assessment invitation verified from Gmail. No later status email was found."},{"id":1013,"company":"Optiver","role":"Software Engineer Internship (2026 Start)","stage":"Technical Assessment","inviteDate":"2026-01-09","interviewDate":"","status":"Withdrawn","priority":"Low","nextAction":"Closed.","followUpDate":"","contact":"Optiver recruiting","mode":"Online assessment","source":"","notes":"Assessment invitation received. Application was closed January 19 because the assessment was not completed by the deadline."},{"id":1014,"company":"Shane Smith Law","role":"AI Specialist (Internship)","stage":"Hiring Manager Interview","inviteDate":"2026-07-23","interviewDate":"2026-07-27","status":"Awaiting Response","priority":"High","nextAction":"Open Indeed to review the new employer message and respond if needed.","followUpDate":"2026-08-07","contact":"Shane Smith Law recruiting","mode":"Zoom / Indeed message","source":"","notes":"Interview completed July 27. A status follow-up was sent August 7, and Indeed notified later that day of a new employer message for this application."},{"id":1015,"company":"Arootah","role":"AI Product Engineer","stage":"Final Decision","inviteDate":"","interviewDate":"","status":"Rejected","priority":"Low","nextAction":"Closed; optionally consider the separate AI Advisory roster opportunity.","followUpDate":"","contact":"Arootah recruiting","mode":"Email","source":"","notes":"Application was not advanced because the role is not currently a priority need; the company suggested a separate advisory roster."},{"id":1016,"company":"Mercor","role":"Computer Vision Expert","stage":"Final Decision","inviteDate":"","interviewDate":"","status":"Rejected","priority":"Low","nextAction":"Closed.","followUpDate":"","contact":"Mercor recruiting","mode":"Email","source":"","notes":"Hiring manager did not advance the application due to project constraints; profile remains in Mercor's candidate pool."},{"id":1017,"company":"Mercor","role":"Machine Learning & NLP Expert","stage":"Final Decision","inviteDate":"","interviewDate":"","status":"Rejected","priority":"Low","nextAction":"Closed.","followUpDate":"","contact":"Mercor recruiting","mode":"Email","source":"","notes":"Hiring manager did not advance the application due to project constraints; profile remains in Mercor's candidate pool."},{"id":1018,"company":"Renesas Electronics","role":"AI Research Engineer Intern","stage":"Final Decision","inviteDate":"","interviewDate":"","status":"Rejected","priority":"Low","nextAction":"Closed.","followUpDate":"","contact":"Renesas recruiting","mode":"Email","source":"","notes":"Renesas confirmed on July 27 that the application would not advance because other candidates were a closer immediate match."},{"id":1019,"company":"Formlabs","role":"2026 (Fall) - Software - Desktop Software Intern","stage":"Final Decision","inviteDate":"2026-07-28","interviewDate":"","status":"Rejected","priority":"Low","nextAction":"Closed.","followUpDate":"","contact":"Formlabs recruiting","mode":"Email","source":"","notes":"Formlabs sent an application update on July 28 confirming that the application would not move forward."},{"id":1020,"company":"HireVue","role":"Data Science Intern | Fully Remote US","stage":"Unknown","inviteDate":"","interviewDate":"","status":"Awaiting Response","priority":"Low","nextAction":"Wait for HireVue to resume active recruiting and provide the next application update.","followUpDate":"","contact":"HireVue recruiting","mode":"Email","source":"","notes":"HireVue confirmed on August 3 that the role remains open but active recruitment and interviews are temporarily paused while applications are reviewed."},{"id":1021,"company":"SMS","role":"Now Hiring for Summer/Fall 2026 Business Coordinator/Intern Position","stage":"Unknown","inviteDate":"","interviewDate":"","status":"Awaiting Response","priority":"Medium","nextAction":"Open Indeed to review and respond to the employer message.","followUpDate":"","contact":"SMS recruiting","mode":"Indeed message","source":"","notes":"Indeed notified on August 4 that SMS sent a new message regarding this application; the notification did not include the message contents."},{"id":1022,"company":"IFS","role":"Forward Deployed Engineer","stage":"Final Decision","inviteDate":"","interviewDate":"","status":"Rejected","priority":"Low","nextAction":"Closed.","followUpDate":"","contact":"IFS recruiting","mode":"Email","source":"","notes":"IFS confirmed on August 6 that the Forward Deployed Engineer application would not move forward after further consideration."},{"id":1023,"company":"Novus Law LLC","role":"Manager, Technology Solutions","stage":"Final Decision","inviteDate":"","interviewDate":"","status":"Rejected","priority":"Low","nextAction":"Closed.","followUpDate":"","contact":"Novus Law recruiting","mode":"Indeed email","source":"","notes":"Novus Law confirmed on August 7 that the application was not selected to advance to the next hiring step."},{"id":1024,"company":"Data Skill Source","role":"AI Prompt Engineer & Agent Builder","stage":"Unknown","inviteDate":"","interviewDate":"","status":"Awaiting Response","priority":"Medium","nextAction":"Open Indeed to review the employer message and respond if needed.","followUpDate":"2026-08-08","contact":"Data Skill Source recruiting","mode":"Indeed message","source":"","notes":"Indeed notified on August 8 that the employer sent a new message regarding this application; the notification did not include the message contents."}];

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

function normalizeKey(value) {
  return String(value || '').trim().toLowerCase();
}

function recordKeys(item) {
  const keys = [];
  if (item && item.id !== undefined && item.id !== null && item.id !== '') {
    keys.push(`id:${item.id}`);
  }
  const company = normalizeKey(item && item.company);
  const role = normalizeKey(item && item.role);
  if (company || role) keys.push(`job:${company}|${role}`);
  return keys;
}

function mergeVerifiedSeed(cloudData) {
  if (!Array.isArray(cloudData) || cloudData.length === 0) return seed;

  const merged = cloudData.map((item) => ({ ...item }));
  const existingKeys = new Set(merged.flatMap(recordKeys));

  for (const verified of seed) {
    const keys = recordKeys(verified);
    if (keys.some((key) => existingKeys.has(key))) continue;
    merged.push({ ...verified });
    keys.forEach((key) => existingKeys.add(key));
  }

  return merged;
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
      const cloudData = JSON.parse(text);
      const resolvedData = mergeVerifiedSeed(cloudData);

      return res.status(200).json({
        data: resolvedData,
        cloud: true,
        updatedAt: result.blob.uploadedAt,
        seeded: resolvedData === seed,
        mergedSeedRecords: Math.max(0, resolvedData.length - (Array.isArray(cloudData) ? cloudData.length : 0)),
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