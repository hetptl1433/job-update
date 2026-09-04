const iconPaths = {
  watch: '<rect x="7" y="5" width="10" height="14" rx="3"/><path d="M9 5l1-3h4l1 3M9 19l1 3h4l1-3"/>',
  chevron: '<path d="m9 6 6 6-6 6"/>',
  refresh: '<path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 4v7h-7"/>',
  "arrow-up-right": '<path d="M7 17 17 7M8 7h9v9"/>',
  sparkles: '<path d="m12 3 1.4 4.2L18 9l-4.6 1.8L12 15l-1.4-4.2L6 9l4.6-1.8z"/><path d="m19 15 .7 2.1L22 18l-2.3.9L19 21l-.7-2.1L16 18l2.3-.9z"/>',
  orbit: '<ellipse cx="12" cy="12" rx="9" ry="4.8" transform="rotate(-18 12 12)"/><circle cx="12" cy="12" r="2"/><circle cx="4.2" cy="15.4" r="1" fill="currentColor" stroke="none"/>',
  bolt: '<path d="m13 2-8 12h6l-1 8 9-13h-6z"/>',
  steps: '<path d="M7.7 11.2c1.5.2 2.2 1.6 1.8 3.1l-.7 2.9c-.4 1.6-2 2.5-3.5 2.1s-2.4-1.9-2-3.5l.8-2.9c.4-1.3 1.8-2 3.6-1.7ZM15.3 4.4c1.5.2 2.2 1.6 1.8 3.1l-.7 2.9c-.4 1.6-2 2.5-3.5 2.1s-2.4-1.9-2-3.5l.8-2.9c.4-1.3 1.8-2 3.6-1.7Z"/>',
  route: '<circle cx="6" cy="17" r="2"/><circle cx="18" cy="7" r="2"/><path d="M8 17h3c4 0 1-10 5-10"/>',
  stairs: '<path d="M4 19h4v-4h4v-4h4V7h4"/>',
  heart: '<path d="M20.8 5.9a5.4 5.4 0 0 0-7.6 0L12 7.1l-1.2-1.2a5.4 5.4 0 0 0-7.6 7.6L12 22l8.8-8.5a5.4 5.4 0 0 0 0-7.6Z"/>',
  "trend-down": '<path d="m4 7 6 6 4-4 6 6"/><path d="M20 10v5h-5"/>',
  "trend-up": '<path d="m4 17 6-6 4 4 6-6"/><path d="M15 9h5v5"/>',
  wave: '<path d="M3 12h3l2-7 4 14 3-10 2 3h4"/>',
  droplet: '<path d="M12 2s7 7.2 7 13a7 7 0 0 1-14 0c0-5.8 7-13 7-13Z"/>',
  temperature: '<path d="M14 14.8V5a4 4 0 0 0-8 0v9.8a6 6 0 1 0 8 0Z"/><path d="M10 6v10"/>',
  moon: '<path d="M20.8 15.1A8.5 8.5 0 0 1 8.9 3.2 9 9 0 1 0 20.8 15Z"/>',
  run: '<circle cx="13" cy="4" r="2"/><path d="m10 21 2-6-3-3 2-5 4 3 4 1M6 21l3-5M12 15l4 5"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  "shield-check": '<path d="M12 22s8-3.8 8-10V5l-8-3-8 3v7c0 6.2 8 10 8 10Z"/><path d="m8.5 12 2.2 2.2 4.8-5"/>',
  activity: '<path d="M4 13h3l2-6 4 11 3-8 2 3h2"/>',
  lungs: '<path d="M12 12V4M10 9 7 5M14 9l3-4"/><path d="M10 12c0 6-2 9-5 9-2 0-3-1.7-3-4 0-4.5 2.6-8 6-9M14 12c0 6 2 9 5 9 2 0 3-1.7 3-4 0-4.5-2.6-8-6-9"/>',
  walk: '<circle cx="12" cy="4" r="2"/><path d="m10 21 1-6-3-3 2-5 4 3 3 1M6 21l3-5M12 15l4 6"/>',
  brain: '<path d="M9.5 4.5A3 3 0 0 0 4 6v1.5A3.5 3.5 0 0 0 3 14a4 4 0 0 0 6.5 3M14.5 4.5A3 3 0 0 1 20 6v1.5a3.5 3.5 0 0 1 1 6.5 4 4 0 0 1-6.5 3M12 3v18M8 9h4M12 14h4"/>',
  lock: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
  home: '<path d="m3 11 9-8 9 8"/><path d="M5 10v10h14V10M9 20v-6h6v6"/>',
  checklist: '<path d="m4 6 1.5 1.5L8 5M11 6h9M4 12l1.5 1.5L8 11M11 12h9M4 18l1.5 1.5L8 17M11 18h9"/>',
  waveform: '<path d="M3 12h2M7 8v8M11 5v14M15 8v8M19 10v4M22 12h-1"/>',
  health: '<path d="M20.8 5.9a5.4 5.4 0 0 0-7.6 0L12 7.1l-1.2-1.2a5.4 5.4 0 0 0-7.6 7.6L12 22l8.8-8.5a5.4 5.4 0 0 0 0-7.6Z"/><path d="M7 12h3l1.2-3 2 6 1.3-3H18"/>',
  grid: '<rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/>',
  close: '<path d="m6 6 12 12M18 6 6 18"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/>',
  chart: '<path d="M4 19V9M10 19V4M16 19v-7M22 19H2"/>',
  flame: '<path d="M12 22c4 0 7-2.7 7-6.4 0-3-1.8-5.3-4-7.6 0 3-1.3 4.2-2.5 4.8.3-4.5-2.1-7.7-5-10.8.2 4-2.5 6.2-2.5 9.8C5 17.4 8 22 12 22Z"/>',
  bed: '<path d="M3 18v-8M21 18v-5a3 3 0 0 0-3-3H9v8M3 14h18M6 10V7h3v3"/>',
  eye: '<path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12Z"/><circle cx="12" cy="12" r="2.5"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-2.8 2.8-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.6v.2h-4V21a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1L4.2 17l.1-.1a1.7 1.7 0 0 0 .3-1.9A1.7 1.7 0 0 0 3 14H2.8v-4H3a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9L4.2 7 7 4.2l.1.1a1.7 1.7 0 0 0 1.9.3A1.7 1.7 0 0 0 10 3V2.8h4V3a1.7 1.7 0 0 0 1 1.6 1.7 1.7 0 0 0 1.9-.3l.1-.1L19.8 7l-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.6 1h.2v4H21a1.7 1.7 0 0 0-1.6 1Z"/>'
};

function iconMarkup(name, size) {
  const iconSize = size || 20;
  return '<svg width="' + iconSize + '" height="' + iconSize + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (iconPaths[name] || "") + "</svg>";
}

function hydrateIcons(root) {
  const scope = root || document;
  if (scope.matches && scope.matches("[data-icon]")) {
    scope.innerHTML = iconMarkup(scope.dataset.icon);
  }
  scope.querySelectorAll("[data-icon]").forEach(function (element) {
    element.innerHTML = iconMarkup(element.dataset.icon);
  });
}

const periodData = {
  today: {
    readinessLabel: "DAILY READINESS",
    activityLabel: "MOVE TODAY",
    vitalsLabel: "RIGHT NOW",
    sleepLabel: "LAST NIGHT",
    sleepKind: "ASLEEP",
    readiness: "82",
    readinessTitle: "Ready for more",
    readinessSummary: "Your recovery signals are above your 30-day baseline.",
    hrvDelta: "+12%",
    sleepScore: "91",
    loadScore: "64",
    guidance: "You have room for a challenging workout before 6 PM.",
    insightTitle: "Your best recovery this week",
    insightBody: "Seven hours of consistent sleep raised HRV while resting heart rate stayed low.",
    move: "620",
    moveGoal: " / 750 kcal",
    exercise: "38",
    exerciseGoal: " / 45 min",
    stand: "9",
    standGoal: " / 12 hr",
    steps: "10,482",
    distance: "5.1 mi",
    floors: "11",
    heartRate: "62",
    hrv: "58",
    sleepDuration: "7h 42m",
    trendAverage: "78 avg",
    rings: [.82, .83, .84, .75],
    bars: [58, 72, 66, 78, 69, 88, 82]
  },
  week: {
    readinessLabel: "7-DAY READINESS",
    activityLabel: "7-DAY TOTAL",
    vitalsLabel: "7-DAY AVERAGE",
    sleepLabel: "7-DAY AVERAGE",
    sleepKind: "NIGHTLY AVG",
    readiness: "78",
    readinessTitle: "A balanced week",
    readinessSummary: "Five of seven days landed within your recovery range.",
    hrvDelta: "+6%",
    sleepScore: "86",
    loadScore: "68",
    guidance: "Keep one lighter day between your next two demanding sessions.",
    insightTitle: "Consistency is doing the work",
    insightBody: "A steadier bedtime was linked with stronger morning recovery on five days.",
    move: "4,280",
    moveGoal: " / 5,250 kcal",
    exercise: "236",
    exerciseGoal: " / 315 min",
    stand: "74",
    standGoal: " / 84 hr",
    steps: "68,214",
    distance: "32.7 mi",
    floors: "73",
    heartRate: "58",
    hrv: "54",
    sleepDuration: "7h 19m",
    trendAverage: "78 avg",
    rings: [.78, .82, .75, .88],
    bars: [58, 72, 66, 78, 69, 88, 82]
  },
  month: {
    readinessLabel: "4-WEEK READINESS",
    activityLabel: "4-WEEK TOTAL",
    vitalsLabel: "4-WEEK AVERAGE",
    sleepLabel: "4-WEEK AVERAGE",
    sleepKind: "NIGHTLY AVG",
    readiness: "75",
    readinessTitle: "Building momentum",
    readinessSummary: "Recovery is trending up as sleep consistency improves.",
    hrvDelta: "+9%",
    sleepScore: "83",
    loadScore: "61",
    guidance: "Your current pattern supports a gradual increase in weekly activity.",
    insightTitle: "A meaningful shift in four weeks",
    insightBody: "Resting heart rate moved down three beats as weekly movement became steadier.",
    move: "17,940",
    moveGoal: " / 21,000 kcal",
    exercise: "948",
    exerciseGoal: " / 1,260 min",
    stand: "301",
    standGoal: " / 336 hr",
    steps: "274k",
    distance: "131 mi",
    floors: "286",
    heartRate: "56",
    hrv: "52",
    sleepDuration: "7h 11m",
    trendAverage: "75 avg",
    rings: [.75, .79, .70, .84],
    bars: [48, 55, 63, 67, 72, 76, 81]
  }
};

function metricCards(items) {
  return '<div class="sheet-metric-grid">' + items.map(function (item) {
    return '<div class="sheet-metric"><span>' + item[0] + '</span><strong>' + item[1] + '</strong><small>' + item[2] + '</small></div>';
  }).join("") + "</div>";
}

function detailList(items) {
  return '<div class="sheet-list">' + items.map(function (item) {
    return '<div><span class="list-icon" data-icon="' + item[0] + '"></span><span><b>' + item[1] + '</b><small>' + item[2] + '</small></span><small>' + item[3] + '</small></div>';
  }).join("") + "</div>";
}

function callout(text) {
  return '<div class="sheet-callout"><span data-icon="info"></span><span>' + text + "</span></div>";
}

const sheets = {
  readiness: {
    icon: "sparkles",
    eyebrow: "EXPLAINED SCORE",
    title: "Daily readiness",
    render: function () {
      const data = periodData[activePeriod];
      const range = activePeriod === "today" ? "TODAY · 6:52 AM" : activePeriod === "week" ? "PAST 7 DAYS" : "PAST 4 WEEKS";
      return '<div class="sheet-hero"><span>' + range + '</span><strong>' + data.readiness + ' · Ready</strong><p>' + data.readinessSummary + ' This score combines trends, not a single reading.</p></div>' +
        '<section class="sheet-section"><h3>What shaped today</h3>' +
        metricCards([["Sleep", data.sleepScore, data.sleepDuration + " · consistent"], ["HRV", data.hrv + " ms", data.hrvDelta + " vs baseline"], ["Resting HR", "54 bpm", "3 below baseline"], ["Recent load", data.loadScore, "Inside optimal range"]]) +
        '</section><section class="sheet-section"><h3>Recommended today</h3>' +
        detailList([["run", "Training capacity", "Room for a challenging session", "Strong"], ["sun", "Best window", "Energy pattern peaks before evening", "2–6 PM"], ["moon", "Protect tonight", "Keep bedtime near your usual time", "10:50 PM"]]) +
        '</section>' + callout("Readiness is an Orbit design concept. The implementation should show “Building your baseline” until enough history exists and explain every contributor.");
    }
  },
  insight: {
    icon: "orbit",
    eyebrow: "ORBIT INSIGHT",
    title: "Why recovery improved",
    render: function () {
      return '<div class="sheet-hero"><span>PERSONAL PATTERN</span><strong>+8 points</strong><p>Your strongest recovery day followed a lighter activity day and a bedtime within 24 minutes of your norm.</p></div>' +
        '<section class="sheet-section"><h3>Signals used</h3>' +
        detailList([["bed", "Sleep duration", "42 minutes above 4-week average", "7h 42m"], ["wave", "Heart-rate variability", "Overnight median", "58 ms"], ["heart", "Resting heart rate", "Stayed within your usual range", "54 bpm"]]) +
        '</section><div class="prompt-grid"><button data-prompt="Plan a workout for my recovery today">Plan a workout for my recovery today →</button><button data-prompt="Explain which health signals changed">Explain which signals changed →</button></div>' +
        callout("Health sharing with Orbit AI should be an explicit, separate opt-in. The prototype keeps that control off by default.");
    }
  },
  activity: {
    icon: "activity",
    eyebrow: "MOVE & TRAIN",
    title: "Activity",
    render: function () {
      const data = periodData[activePeriod];
      const range = activePeriod === "today" ? "TODAY" : activePeriod === "week" ? "PAST 7 DAYS" : "PAST 4 WEEKS";
      return '<div class="sheet-hero"><span>' + range + '</span><strong>' + data.steps + ' steps</strong><p>Move, Exercise, and Stand are shown against the goals for this selected range.</p></div>' +
        '<section class="sheet-section"><h3>Today at a glance</h3>' +
        metricCards([["Active energy", data.move + " kcal", data.moveGoal.replace(" / ", "Goal ")], ["Exercise", data.exercise + " min", data.exerciseGoal.replace(" / ", "Goal ")], ["Distance", data.distance, "Selected range"], ["Floors", data.floors, "Selected range"]]) +
        '</section><section class="sheet-section"><h3>Movement quality</h3>' +
        detailList([["sun", "Time in daylight", "Outdoor exposure today", "54 min"], ["walk", "Walking pace", "Average across 2.8 miles", "17:42/mi"], ["stairs", "Flights climbed", "Three more than yesterday", "11"]]) +
        '</section>';
    }
  },
  heart: {
    icon: "heart",
    eyebrow: "HEART & CARDIO",
    title: "Heart",
    render: function () {
      const data = periodData[activePeriod];
      const range = activePeriod === "today" ? "LATEST SAMPLE · 9:36 AM" : activePeriod === "week" ? "7-DAY AVERAGE" : "4-WEEK AVERAGE";
      return '<div class="sheet-hero"><span>' + range + '</span><strong>' + data.heartRate + ' bpm</strong><p>Your recent heart-rate values are inside your personal range.</p></div>' +
        '<section class="sheet-section"><h3>Heart metrics</h3>' +
        metricCards([["Resting HR", "54 bpm", "30-day baseline 57"], ["Walking avg", "91 bpm", "Stable this month"], ["HRV", "58 ms", "12% above baseline"], ["Cardio fitness", "42.8", "VO₂ max · above avg"]]) +
        '</section><section class="sheet-section"><h3>Recent signals</h3>' +
        detailList([["heart", "Daily range", "Lowest to highest detected", "49–141"], ["run", "Cardio recovery", "One minute after workout", "31 bpm"], ["shield-check", "Heart notifications", "No recent high, low, or irregular alerts", "Clear"]]) +
        '</section>' + callout("Latest heart rate must always include a timestamp. Old samples should never be presented as live.");
    }
  },
  hrv: {
    icon: "wave",
    eyebrow: "RECOVERY SIGNAL",
    title: "Heart-rate variability",
    render: function () {
      return '<div class="sheet-hero"><span>OVERNIGHT MEDIAN</span><strong>58 ms</strong><p>Twelve percent above your 30-day baseline. Higher or lower is personal; the trend matters most.</p></div>' +
        '<section class="sheet-section"><h3>Context</h3>' +
        metricCards([["30-day baseline", "48 ms", "Your usual range 41–59"], ["7-day average", "54 ms", "Up 6%"], ["Best night", "61 ms", "Tuesday"], ["Data coverage", "7 / 7", "Nights recorded"]]) +
        '</section>' + callout("HRV can vary with sleep, training, stress, alcohol, illness, and measurement timing. Orbit should describe patterns without diagnosing.");
    }
  },
  vitals: {
    icon: "wave",
    eyebrow: "OVERNIGHT & RECENT",
    title: "Vitals",
    render: function () {
      return '<div class="sheet-hero"><span>4 OF 4 AVAILABLE</span><strong>Steady</strong><p>Your overnight and recent measurements are within their usual personal ranges.</p></div>' +
        '<section class="sheet-section"><h3>Latest measurements</h3>' +
        detailList([["heart", "Resting heart rate", "Overnight low and waking trend", "54 bpm"], ["wave", "Heart-rate variability", "Overnight median", "58 ms"], ["lungs", "Respiratory rate", "During sleep", "14.2/min"], ["droplet", "Blood oxygen", "Latest supported reading", "97%"], ["temperature", "Wrist temperature", "Change from baseline", "+0.1°"]]) +
        '</section>' + callout("Blood oxygen and wrist temperature depend on supported hardware, region, source data, and granted access. Unavailable cards should disappear, not show zero.");
    }
  },
  oxygen: {
    icon: "droplet",
    eyebrow: "RECENT VITAL",
    title: "Blood oxygen",
    render: function () {
      return '<div class="sheet-hero"><span>LATEST SUPPORTED READING</span><strong>97%</strong><p>Recent values range from 95–99%. Availability varies by Watch model and region.</p></div>' +
        '<section class="sheet-section"><h3>Recent context</h3>' + metricCards([["Today", "97%", "9:12 AM"], ["Overnight range", "95–98%", "6 readings"], ["7-day range", "94–99%", "When available"], ["Source", "Watch", "Series / region dependent"]]) + '</section>' +
        callout("Orbit should use neutral language such as “outside your usual range” and never use this measurement alone for medical conclusions.");
    }
  },
  temperature: {
    icon: "temperature",
    eyebrow: "OVERNIGHT VITAL",
    title: "Wrist temperature",
    render: function () {
      return '<div class="sheet-hero"><span>CHANGE FROM BASELINE</span><strong>+0.1°</strong><p>Within your usual overnight range. Wrist temperature is shown as a deviation, not a core body temperature.</p></div>' +
        '<section class="sheet-section"><h3>Baseline</h3>' + metricCards([["Last night", "+0.1°", "Within range"], ["7-day avg", "0.0°", "Stable"], ["Baseline nights", "24", "Enough coverage"], ["Latest sample", "5:58 AM", "Apple Watch"]]) + '</section>';
    }
  },
  sleep: {
    icon: "moon",
    eyebrow: "LAST NIGHT",
    title: "Sleep",
    render: function () {
      const data = periodData[activePeriod];
      const range = activePeriod === "today" ? "10:48 PM – 6:52 AM" : activePeriod === "week" ? "7-DAY NIGHTLY AVERAGE" : "4-WEEK NIGHTLY AVERAGE";
      return '<div class="sheet-hero"><span>' + range + '</span><strong>' + data.sleepDuration + '</strong><p>Strong duration, efficient sleep, and timing close to your personal schedule.</p></div>' +
        '<section class="sheet-section"><h3>Sleep stages</h3>' +
        metricCards([["REM", "1h 34m", "20% of sleep"], ["Core", "4h 46m", "62% of sleep"], ["Deep", "1h 22m", "18% of sleep"], ["Awake", "22 min", "4 brief periods"]]) +
        '</section><section class="sheet-section"><h3>Quality factors</h3>' +
        detailList([["chart", "Efficiency", "Time asleep while in bed", "96%"], ["moon", "Consistency", "Within 24m of usual bedtime", "Great"], ["heart", "Sleeping heart rate", "Personal range 48–57", "51 bpm"], ["lungs", "Respiratory rate", "Personal range 13.4–15.1", "14.2"]]) +
        '</section>';
    }
  },
  training: {
    icon: "run",
    eyebrow: "LOAD & RECOVERY",
    title: "Training",
    render: function () {
      return '<div class="sheet-hero"><span>7-DAY LOAD</span><strong>64 · Optimal</strong><p>Your activity load is productive without outpacing recent recovery.</p></div>' +
        '<section class="sheet-section"><h3>Latest workout</h3>' +
        detailList([["run", "Outdoor Run", "4.2 mi · 38 min · 9:03/mi", "412 kcal"], ["heart", "Heart rate", "Average 134 · peak 158", "Zone 2–3"], ["route", "Elevation gain", "Rolling outdoor route", "184 ft"]]) +
        '</section><section class="sheet-section"><h3>Training signals</h3>' +
        metricCards([["Cardio load", "64", "Inside optimal range"], ["Recovery", "82", "Ready for more"], ["Weekly workouts", "4", "1 more than average"], ["Cardio fitness", "42.8", "VO₂ max"]]) +
        '</section>';
    }
  },
  trends: {
    icon: "chart",
    eyebrow: "PERSONAL BASELINES",
    title: "Trends",
    render: function () {
      return '<div class="sheet-hero"><span>LAST 4 WEEKS</span><strong>3 improving</strong><p>Sleep consistency, HRV, and cardio fitness are moving in a positive direction.</p></div>' +
        '<section class="sheet-section"><h3>Meaningful changes</h3>' +
        detailList([["moon", "Sleep consistency", "6 of 7 nights near schedule", "+9%"], ["wave", "Heart-rate variability", "Four-week rolling average", "+6%"], ["heart", "Resting heart rate", "Four-week rolling average", "−3 bpm"], ["run", "Cardio fitness", "Estimated VO₂ max", "+1.2"]]) +
        '</section>' + callout("Trends should compare the user with their own baseline, not other people. Every insight needs data coverage and source context.");
    }
  },
  signals: {
    icon: "shield-check",
    eyebrow: "QUIET MONITORING",
    title: "Health signals",
    render: function () {
      return '<div class="sheet-hero"><span>RECENT DATA</span><strong>All clear</strong><p>No unusual changes are visible across the signals you chose to monitor.</p></div>' +
        '<section class="sheet-section"><h3>Monitored signals</h3>' +
        detailList([["heart", "High / low heart rate", "No recent notification data", "Clear"], ["wave", "Irregular rhythm", "When available from Apple Health", "Clear"], ["droplet", "Blood oxygen range", "Supported readings only", "Steady"], ["sun", "Environmental sound", "No high-exposure event", "Clear"]]) +
        '</section>' + callout("Orbit should surface Apple-recorded notifications and trends, not claim to replace emergency or medical monitoring.");
    }
  },
  browse: {
    icon: "grid",
    eyebrow: "ALL CATEGORIES",
    title: "Browse health data",
    render: function () {
      return '<section class="sheet-section"><h3>Pinned to overview</h3>' +
        detailList([["heart", "Heart", "Rate, resting rate, HRV, recovery", "8"], ["activity", "Activity", "Energy, steps, exercise, stand", "12"], ["moon", "Sleep", "Stages, duration, timing, trends", "7"], ["lungs", "Respiratory", "Rate, oxygen, fitness", "5"]]) +
        '</section><section class="sheet-section"><h3>More categories</h3>' +
        detailList([["walk", "Mobility", "Speed, steadiness, asymmetry", "6"], ["brain", "Mind & body", "Mindfulness, state of mind, daylight", "9"], ["wave", "Hearing", "Environmental and headphone sound", "3"], ["chart", "Body measurements", "Weight, BMI, composition", "5"]]) +
        '</section>' + callout("Only categories with recent, authorized data should appear on the main dashboard. Sensitive categories should be opt-in and pinnable.");
    }
  },
  mobility: {
    icon: "walk",
    eyebrow: "MOVEMENT QUALITY",
    title: "Mobility",
    render: function () {
      return '<div class="sheet-hero"><span>7-DAY VIEW</span><strong>Steady</strong><p>Walking pace and symmetry are close to your personal baseline.</p></div>' +
        '<section class="sheet-section"><h3>Available metrics</h3>' + metricCards([["Walking speed", "3.4 mph", "Stable"], ["Step length", "27.8 in", "Usual range"], ["Asymmetry", "1.2%", "Low"], ["Double support", "24.1%", "Stable"]]) + '</section>';
    }
  },
  mind: {
    icon: "brain",
    eyebrow: "WELLBEING",
    title: "Mind & body",
    render: function () {
      return '<div class="sheet-hero"><span>TODAY</span><strong>12 mindful min</strong><p>A quiet place for mindfulness, daylight, state of mind, and other user-selected wellbeing signals.</p></div>' +
        '<section class="sheet-section"><h3>Today</h3>' + detailList([["brain", "Mindful minutes", "Two breathing sessions", "12 min"], ["sun", "Time in daylight", "Outdoor exposure", "54 min"], ["moon", "Wind-down routine", "Started near usual time", "10:21 PM"]]) + '</section>' +
        callout("Sensitive wellbeing categories should never be placed on the overview without an explicit user choice.");
    }
  },
  device: {
    icon: "watch",
    eyebrow: "SOURCES & PRIVACY",
    title: "Apple Health",
    render: function () {
      return '<div class="sheet-hero"><span>CONNECTED SOURCE</span><strong>Watch samples</strong><p>Latest Apple Watch sample was available two minutes ago. Data remains controlled through Apple Health.</p></div>' +
        '<section class="sheet-section"><h3>Data coverage</h3>' +
        metricCards([["Recent signals", "27", "With available data"], ["Baseline", "24 days", "Still improving"], ["Latest sample", "2m ago", "Apple Watch"], ["Workouts", "42", "Last 90 days"]]) +
        '</section><section class="sheet-section"><h3>Preferences</h3>' +
        '<div class="settings-row"><span><b>Share summaries with Orbit AI</b><small>Off by default · never required for health tracking</small></span><button class="toggle" id="aiShareToggle" aria-pressed="false" aria-label="Share health summaries with Orbit AI"></button></div>' +
        '<div class="settings-row"><span><b>Weekly health briefing</b><small>Private summary every Sunday morning</small></span><button class="toggle on" id="briefingToggle" aria-pressed="true" aria-label="Weekly health briefing"></button></div>' +
        '<div class="settings-row"><span><b>Dark appearance</b><small>Preview the Health tab in dark mode</small></span><button class="toggle" id="themeToggle" aria-pressed="false" aria-label="Dark appearance"></button></div>' +
        '</section><button class="sheet-primary" id="manageAccessButton">Manage access in Apple Health</button>' +
        callout("“Connected” does not mean every category was approved. HealthKit intentionally does not reveal whether read access was denied or data is simply absent.");
    }
  },
  assistant: {
    icon: "orbit",
    eyebrow: "ORBIT VOICE",
    title: "Ask about your health",
    render: function () {
      return '<div class="sheet-hero"><span>PRIVATE CONTEXT CONTROL</span><strong>What can I help with?</strong><p>Choose a prompt to preview a health-aware Orbit conversation.</p></div>' +
        '<div class="prompt-grid"><button data-prompt="How recovered am I today?">How recovered am I today?</button><button data-prompt="Plan a workout around my recovery">Plan a workout around my recovery</button><button data-prompt="What changed in my sleep this week?">What changed in my sleep this week?</button><button data-prompt="Summarize my health trends">Summarize my health trends</button></div>' +
        callout("The production app should ask before sending any Health context to an AI service. This prototype does not send or store health data.");
    }
  }
};

let activePeriod = "today";
let lastFocusedElement = null;
let toastTimer = null;

function setCircleProgress(circle, progress) {
  if (!circle) return;
  const radius = Number(circle.getAttribute("r"));
  const circumference = 2 * Math.PI * radius;
  circle.style.strokeDasharray = String(circumference);
  circle.style.strokeDashoffset = String(circumference);
  requestAnimationFrame(function () {
    requestAnimationFrame(function () {
      circle.style.strokeDashoffset = String(circumference * (1 - progress));
    });
  });
}

function updateRings(values) {
  setCircleProgress(document.getElementById("readinessRing"), values[0]);
  setCircleProgress(document.getElementById("moveRing"), values[1]);
  setCircleProgress(document.getElementById("exerciseRing"), values[2]);
  setCircleProgress(document.getElementById("standRing"), values[3]);
}

function renderPeriod(period) {
  activePeriod = period;
  const data = periodData[period];
  document.querySelectorAll("[data-bind]").forEach(function (element) {
    const key = element.dataset.bind;
    if (Object.prototype.hasOwnProperty.call(data, key)) {
      element.textContent = data[key];
    }
  });
  document.querySelectorAll(".period-button").forEach(function (button, index) {
    const selected = button.dataset.period === period;
    button.classList.toggle("active", selected);
    button.setAttribute("aria-selected", String(selected));
    if (selected) document.querySelector(".period-switch").dataset.index = String(index);
  });
  const labels = {
    today: new Intl.DateTimeFormat("en-US", { weekday: "long", month: "short", day: "numeric" }).format(new Date()).toUpperCase(),
    week: "PAST 7 DAYS",
    month: "PAST 4 WEEKS"
  };
  document.getElementById("dateEyebrow").textContent = labels[period];
  const bars = document.querySelectorAll("#weeklyBars i");
  data.bars.forEach(function (height, index) {
    if (bars[index]) bars[index].style.height = height + "%";
  });
  document.getElementById("loadMarker").style.left = data.loadScore + "%";
  const readinessRing = document.querySelector(".readiness-ring");
  readinessRing.setAttribute("aria-label", "Readiness score " + data.readiness + " out of 100");
  document.getElementById("activityRings").setAttribute(
    "aria-label",
    "Move " + Math.round(data.rings[1] * 100) + " percent, exercise " + Math.round(data.rings[2] * 100) + " percent, stand " + Math.round(data.rings[3] * 100) + " percent"
  );
  updateRings(data.rings);
}

function openSheet(name, trigger) {
  const config = sheets[name] || sheets.browse;
  lastFocusedElement = trigger || document.activeElement;
  document.getElementById("sheetEyebrow").textContent = config.eyebrow;
  document.getElementById("sheetTitle").textContent = config.title;
  const sheetIcon = document.getElementById("sheetIcon");
  sheetIcon.dataset.icon = config.icon;
  const content = document.getElementById("sheetContent");
  content.innerHTML = config.render();
  hydrateIcons(sheetIcon);
  hydrateIcons(content);
  document.getElementById("sheetBackdrop").hidden = false;
  document.getElementById("detailSheet").scrollTop = 0;
  bindDynamicSheetControls();
  requestAnimationFrame(function () {
    document.getElementById("closeSheet").focus();
  });
}

function closeSheet() {
  document.getElementById("sheetBackdrop").hidden = true;
  if (lastFocusedElement && typeof lastFocusedElement.focus === "function") {
    lastFocusedElement.focus();
  }
}

function showToast(message) {
  const toast = document.getElementById("toast");
  clearTimeout(toastTimer);
  toast.textContent = message;
  toast.hidden = false;
  toastTimer = setTimeout(function () {
    toast.hidden = true;
  }, 2200);
}

function toggleControl(button, forcedState) {
  const next = typeof forcedState === "boolean" ? forcedState : !button.classList.contains("on");
  button.classList.toggle("on", next);
  button.setAttribute("aria-pressed", String(next));
  return next;
}

function bindDynamicSheetControls() {
  const themeToggle = document.getElementById("themeToggle");
  if (themeToggle) {
    const dark = document.getElementById("phoneShell").classList.contains("dark-theme");
    toggleControl(themeToggle, dark);
    themeToggle.addEventListener("click", function () {
      const enabled = toggleControl(themeToggle);
      document.getElementById("phoneShell").classList.toggle("dark-theme", enabled);
    });
  }
  ["aiShareToggle", "briefingToggle"].forEach(function (id) {
    const toggle = document.getElementById(id);
    if (toggle) {
      toggle.addEventListener("click", function () {
        const enabled = toggleControl(toggle);
        showToast(id === "aiShareToggle" ? (enabled ? "Health summaries enabled for Orbit AI" : "Health summaries remain private") : (enabled ? "Weekly briefing enabled" : "Weekly briefing paused"));
      });
    }
  });
  const manageButton = document.getElementById("manageAccessButton");
  if (manageButton) {
    manageButton.addEventListener("click", function () {
      showToast("This will open Apple Health settings in the iOS app");
    });
  }
  document.querySelectorAll("[data-prompt]").forEach(function (button) {
    button.addEventListener("click", function () {
      showToast("Orbit prompt ready: “" + button.dataset.prompt + "”");
    });
  });
}

function bindInteractions() {
  document.querySelectorAll("[data-period]").forEach(function (button) {
    button.addEventListener("click", function () {
      renderPeriod(button.dataset.period);
    });
  });

  document.querySelectorAll("[data-sheet]").forEach(function (element) {
    element.addEventListener("click", function (event) {
      event.stopPropagation();
      openSheet(element.dataset.sheet, element);
    });
    if (element.getAttribute("role") === "button" && element.tagName !== "BUTTON") {
      element.addEventListener("keydown", function (event) {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          openSheet(element.dataset.sheet, element);
        }
      });
    }
  });

  document.getElementById("closeSheet").addEventListener("click", closeSheet);
  document.getElementById("sheetBackdrop").addEventListener("click", function (event) {
    if (event.target === event.currentTarget) closeSheet();
  });
  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape" && !document.getElementById("sheetBackdrop").hidden) closeSheet();
  });

  document.querySelectorAll("[data-destination]").forEach(function (button) {
    button.addEventListener("click", function () {
      showToast(button.dataset.destination + " remains unchanged in this Health design pass");
    });
  });

  document.querySelector(".brand-button").addEventListener("click", function () {
    showToast("Orbit home remains unchanged in this design pass");
  });

  document.getElementById("refreshButton").addEventListener("click", function () {
    const button = document.getElementById("refreshButton");
    const status = document.querySelector(".watch-status small");
    button.classList.add("refreshing");
    status.innerHTML = "<i></i> Checking latest samples…";
    setTimeout(function () {
      button.classList.remove("refreshing");
      status.innerHTML = "<i></i> Latest sample now";
      showToast("Health data is up to date");
      setTimeout(function () {
        status.innerHTML = "<i></i> Latest sample 2m ago";
      }, 2400);
    }, 850);
  });
}

function setClock() {
  const now = new Date();
  document.getElementById("statusTime").textContent = now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

hydrateIcons();
setClock();
bindInteractions();
const previewParams = new URLSearchParams(window.location.search);
if (previewParams.get("theme") === "dark") {
  document.getElementById("phoneShell").classList.add("dark-theme");
}
if (periodData[previewParams.get("period")]) {
  activePeriod = previewParams.get("period");
}
renderPeriod(activePeriod);
if (sheets[previewParams.get("sheet")]) {
  openSheet(previewParams.get("sheet"));
}
const previewScroll = Number(previewParams.get("scroll"));
if (Number.isFinite(previewScroll) && previewScroll > 0) {
  requestAnimationFrame(function () {
    document.getElementById("healthScroller").scrollTop = previewScroll;
  });
}
