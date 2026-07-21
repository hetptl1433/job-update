const { get, put } = require('@vercel/blob');

const seed = [
  {id:1001,company:'Western Digital',role:'Fall 2026 Intern - IT Wafer Systems Automation',stage:'Recruiter Screen',inviteDate:'2026-07-15',interviewDate:'',status:'Need Status Update',priority:'High',nextAction:'Wait for the recruiter to confirm an interview time; follow up again if there is no reply.',followUpDate:'2026-07-23',contact:'Western Digital recruiting',mode:'TBD',source:'',notes:'Interview availability requested by email. Availability was sent July 15 and a follow-up was sent July 21.'},
  {id:1002,company:'SNAP Life Sciences',role:'Internship Opportunity',stage:'Offer / Onboarding',inviteDate:'2026-07-06',interviewDate:'2026-07-06',status:'Offer Received',priority:'High',nextAction:'Review the offer letter and internship agreement and confirm acceptance/start details.',followUpDate:'2026-07-22',contact:'SNAP Life Sciences recruiting',mode:'Microsoft Teams',source:'',notes:'Teams interview invitation received July 6. Offer letter and internship agreement received July 8.'},
  {id:1003,company:'Dometic',role:'Quality Engineering Intern',stage:'Offer / Onboarding',inviteDate:'2026-04-30',interviewDate:'2026-05-01',status:'Offer Accepted / Active',priority:'High',nextAction:'Continue the active internship and keep major milestones documented.',followUpDate:'',contact:'Dometic recruiting',mode:'Teams / Elkhart, IN',source:'',notes:'Interview, offer, pre-boarding, orientation, and active start were verified from recruiting emails.'},
  {id:1004,company:'Experian',role:'AI SWE Summer Intern (Remote & Paid)',stage:'One-way Video',inviteDate:'2026-03-23',interviewDate:'2026-03-23',status:'Rejected',priority:'Medium',nextAction:'Closed.',followUpDate:'',contact:'Experian hiring team',mode:'Online video interview',source:'',notes:'Assessment and video interview invitation received; rejection update received April 28.'},
  {id:1005,company:'Experian',role:'ML Engineer Summer Intern (Remote & Paid)',stage:'One-way Video',inviteDate:'2026-04-22',interviewDate:'2026-04-22',status:'Rejected',priority:'Medium',nextAction:'Closed.',followUpDate:'',contact:'Experian hiring team',mode:'Online video interview',source:'',notes:'Assessment and video interview invitation received; rejection update received May 7.'},
  {id:1006,company:'MMI',role:'Full-stack Web Developer Intern',stage:'Hiring Manager Interview',inviteDate:'2026-04-27',interviewDate:'2026-04-28',status:'Need Status Update',priority:'High',nextAction:'Send a final status follow-up or close as no response if the role is no longer active.',followUpDate:'2026-07-22',contact:'MMI recruiting',mode:'Google Meet',source:'',notes:'Interview completed April 28. A follow-up was sent May 16, with no later decision found in Gmail.'},
  {id:1007,company:'Lavner Education',role:'STEM Instructor / Intern',stage:'One-way Video',inviteDate:'2026-04-21',interviewDate:'2026-04-21',status:'Rejected',priority:'Low',nextAction:'Closed.',followUpDate:'',contact:'Lavner Education recruiting',mode:'Online interview',source:'',notes:'Interview invitation received April 21. Position update indicating non-selection received April 23.'},
  {id:1008,company:'Lavner Education',role:'Instructor / Intern - Summer Camps',stage:'Final Interview',inviteDate:'2026-04-25',interviewDate:'2026-04-27',status:'Need Status Update',priority:'Medium',nextAction:'Confirm the outcome of the final interview and the later May 6 interview invitation.',followUpDate:'2026-07-22',contact:'Lavner Education recruiting',mode:'Online interview',source:'',notes:'Initial interview invitation received April 25, final interview invitation April 27, and another interview invitation May 6. No later decision was found.'},
  {id:1009,company:'APR Consulting',role:'Embedded Software Engineer with Active Secret Clearance',stage:'Recruiter Screen',inviteDate:'2026-07-01',interviewDate:'',status:'Need Status Update',priority:'Medium',nextAction:'Confirm whether the virtual recruiter voice screening was completed and request the current status.',followUpDate:'2026-07-22',contact:'APR Consulting recruiting',mode:'Virtual voice screening',source:'',notes:'Voice-screening invitation received July 1 and reminder received July 2.'},
  {id:1010,company:'Amazon',role:'Jr. Software Development Engineer - Jr. Developer Program',stage:'Technical Assessment',inviteDate:'2026-03-19',interviewDate:'2026-03-22',status:'Need Status Update',priority:'Medium',nextAction:'Check the Amazon Jobs portal for the assessment outcome and current application state.',followUpDate:'2026-07-22',contact:'Amazon Jobs',mode:'Online assessment',source:'',notes:'Assessment invitation received March 19 and completion confirmation received March 22. No later decision was found for this specific application.'},
  {id:1011,company:'Citadel / Citadel Securities',role:'Software Engineering Campus Assessment 2025-2026',stage:'Technical Assessment',inviteDate:'2026-01-09',interviewDate:'',status:'Need Status Update',priority:'Low',nextAction:'Check whether the HackerRank assessment was completed and close or update the application accordingly.',followUpDate:'2026-07-22',contact:'Citadel hiring team',mode:'HackerRank',source:'',notes:'HackerRank assessment invitation verified from Gmail. No later status email was found.'},
  {id:1012,company:'Interactive Brokers',role:'Behavioral Assessment',stage:'Technical Assessment',inviteDate:'2026-01-05',interviewDate:'',status:'Need Status Update',priority:'Low',nextAction:'Confirm whether the Predictive Index assessment was completed and update the application status.',followUpDate:'2026-07-22',contact:'Interactive Brokers recruiting',mode:'Predictive Index assessment',source:'',notes:'Behavioral assessment invitation verified from Gmail. No later status email was found.'},
  {id:1013,company:'Optiver',role:'Software Engineer Internship (2026 Start)',stage:'Technical Assessment',inviteDate:'2026-01-09',interviewDate:'',status:'Withdrawn',priority:'Low',nextAction:'Closed.',followUpDate:'',contact:'Optiver recruiting',mode:'Online assessment',source:'',notes:'Assessment invitation received. Application was closed January 19 because the assessment was not completed by the deadline.'}
];

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
      const resolvedData = Array.isArray(data) && data.length > 0 ? data : seed;

      return res.status(200).json({
        data: resolvedData,
        cloud: true,
        updatedAt: result.blob.uploadedAt,
        seeded: resolvedData === seed,
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