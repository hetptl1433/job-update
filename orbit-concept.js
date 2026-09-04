(() => {
  const stroke = (paths, viewBox = "0 0 24 24") => `<svg viewBox="${viewBox}" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;
  const icons = {
    spark: stroke('<path d="M12 2l1.5 5.2L19 9l-5.5 1.8L12 16l-1.5-5.2L5 9l5.5-1.8L12 2Z"/><path d="M19 15l.7 2.3L22 18l-2.3.7L19 21l-.7-2.3L16 18l2.3-.7L19 15Z"/>'),
    sun: stroke('<circle cx="12" cy="12" r="3.6"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>'),
    arrow: stroke('<path d="M5 12h13M14 7l5 5-5 5"/>'),
    chevron: stroke('<path d="m9 18 6-6-6-6"/>'),
    video: stroke('<rect x="3" y="6" width="13" height="12" rx="3"/><path d="m16 10 5-3v10l-5-3"/>'),
    "arrow-up": stroke('<path d="M7 17 17 7M8 7h9v9"/>'),
    check: stroke('<path d="m5 12 4 4L19 6"/>'),
    inbox: stroke('<path d="M4 4h16v14H4z"/><path d="M4 13h4l2 3h4l2-3h4"/>'),
    heart: stroke('<path d="M20.8 5.7a5.2 5.2 0 0 0-7.4 0L12 7.1l-1.4-1.4a5.2 5.2 0 1 0-7.4 7.4L12 21l8.8-7.9a5.2 5.2 0 0 0 0-7.4Z"/>'),
    moon: stroke('<path d="M20.4 15.1A8.7 8.7 0 0 1 8.9 3.6 9 9 0 1 0 20.4 15.1Z"/>'),
    wallet: stroke('<path d="M4 6h14a2 2 0 0 1 2 2v10H4a2 2 0 0 1-2-2V6a3 3 0 0 1 3-3h12"/><path d="M15 11h5v4h-5a2 2 0 1 1 0-4Z"/>'),
    waveform: stroke('<path d="M4 14v-4M8 17V7M12 20V4M16 17V7M20 14v-4"/>'),
    plus: stroke('<path d="M12 5v14M5 12h14"/>'),
    bolt: stroke('<path d="m13 2-8 12h7l-1 8 8-12h-7l1-8Z"/>'),
    play: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="m8 5 11 7-11 7V5Z"/></svg>',
    clock: stroke('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
    "check-circle": stroke('<circle cx="12" cy="12" r="9"/><path d="m8 12 2.5 2.5L16 9"/>'),
    more: stroke('<circle cx="5" cy="12" r="1" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1" fill="currentColor" stroke="none"/><circle cx="19" cy="12" r="1" fill="currentColor" stroke="none"/>'),
    home: stroke('<path d="m3 11 9-8 9 8"/><path d="M5 10v10h14V10M9 20v-6h6v6"/>'),
    checklist: stroke('<path d="m4 6 1.5 1.5L8 5M11 6h9M4 12l1.5 1.5L8 11M11 12h9M4 18l1.5 1.5L8 17M11 18h9"/>'),
    briefcase: stroke('<rect x="3" y="7" width="18" height="13" rx="3"/><path d="M8 7V4h8v3M3 12h18M10 12v2h4v-2"/>'),
    grid: stroke('<rect x="4" y="4" width="6" height="6" rx="2"/><rect x="14" y="4" width="6" height="6" rx="2"/><rect x="4" y="14" width="6" height="6" rx="2"/><rect x="14" y="14" width="6" height="6" rx="2"/>'),
    close: stroke('<path d="m6 6 12 12M18 6 6 18"/>'),
    history: stroke('<path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5M12 7v5l3 2"/>'),
    stop: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><rect x="7" y="7" width="10" height="10" rx="2"/></svg>',
    calendar: stroke('<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M8 3v4M16 3v4M3 10h18"/>'),
    brain: stroke('<path d="M9.5 4a3 3 0 0 0-5 2.2A3.5 3.5 0 0 0 4 13a3 3 0 0 0 3 5 3 3 0 0 0 5 2V6a3 3 0 0 0-2.5-2Z"/><path d="M14.5 4a3 3 0 0 1 5 2.2A3.5 3.5 0 0 1 20 13a3 3 0 0 1-3 5 3 3 0 0 1-5 2V6a3 3 0 0 1 2.5-2ZM8 9a3 3 0 0 0 4 0M16 9a3 3 0 0 1-4 0M8 15a3 3 0 0 1 4 0M16 15a3 3 0 0 0-4 0"/>'),
    link: stroke('<path d="M10 13a5 5 0 0 0 7.1.1l2-2a5 5 0 0 0-7.1-7.1l-1.1 1.1"/><path d="M14 11a5 5 0 0 0-7.1-.1l-2 2A5 5 0 0 0 12 20l1.1-1.1"/>'),
    settings: stroke('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-2.8 2.8-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.6v.2h-4V21a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1L4.2 17l.1-.1a1.7 1.7 0 0 0 .3-1.9A1.7 1.7 0 0 0 3 14H2.8v-4H3a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9L4.2 7 7 4.2l.1.1A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-1.6v-.2h4V3a1.7 1.7 0 0 0 1 1.6 1.7 1.7 0 0 0 1.9-.3l.1-.1L19.8 7l-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.6 1h.2v4H21a1.7 1.7 0 0 0-1.6 1Z"/>')
  };

  function renderIcons(root = document) {
    root.querySelectorAll("[data-icon]").forEach((node) => {
      const icon = icons[node.dataset.icon];
      if (icon) node.innerHTML = icon;
    });
  }

  renderIcons();

  const now = new Date();
  const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const timeNode = document.getElementById("statusTime");
  const dateNode = document.getElementById("dateEyebrow");
  const spendingMonth = document.getElementById("spendingMonth");
  if (timeNode) timeNode.textContent = now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
  if (dateNode) dateNode.textContent = now.toLocaleDateString([], { weekday: "long", month: "short", day: "numeric" }).toUpperCase().replace(",", " ·");
  if (spendingMonth) spendingMonth.textContent = now.toLocaleDateString([], { month: "long" }).toUpperCase();

  const dateButtons = [...document.querySelectorAll(".date-strip button")];
  dateButtons.forEach((button, index) => {
    const date = new Date(now);
    date.setDate(now.getDate() + index - 3);
    const isToday = index === 3;
    button.querySelector("span").textContent = isToday ? "TODAY" : date.toLocaleDateString([], { weekday: "short" }).toUpperCase();
    button.querySelector("b").textContent = String(date.getDate());
    button.classList.toggle("active", isToday);
    button.setAttribute("aria-pressed", String(isToday));
    button.setAttribute("aria-label", `${isToday ? "Today, " : ""}${date.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" })}`);
  });

  const screens = [...document.querySelectorAll("[data-app-screen]")];
  const dockTabs = [...document.querySelectorAll(".dock-tab[data-screen]")];
  const railTabs = [...document.querySelectorAll(".rail-screen[data-screen]")];
  const screenViewport = document.getElementById("screenViewport");
  const screenOrder = ["home", "finance", "health", "tasks", "jobs", "more"];
  let currentScreen = "home";

  function activateScreen(name, options = {}) {
    if (!screenOrder.includes(name)) return;
    const previousIndex = screenOrder.indexOf(currentScreen);
    const nextIndex = screenOrder.indexOf(name);
    const target = screens.find((screen) => screen.dataset.appScreen === name);
    if (!target) return;

    screens.forEach((screen) => {
      screen.classList.remove("active", "enter-back");
      screen.setAttribute("aria-hidden", screen === target ? "false" : "true");
    });
    target.classList.add("active");
    if (nextIndex < previousIndex) target.classList.add("enter-back");

    const primaryDestination = ["tasks", "jobs"].includes(name) ? "more" : name;
    dockTabs.forEach((tab) => {
      const active = tab.dataset.screen === primaryDestination;
      tab.classList.toggle("active", active);
      if (active) tab.setAttribute("aria-current", "page");
      else tab.removeAttribute("aria-current");
    });
    railTabs.forEach((tab) => {
      const active = tab.dataset.screen === name;
      tab.classList.toggle("active", active);
      tab.setAttribute("aria-selected", String(active));
      tab.tabIndex = active ? 0 : -1;
    });
    currentScreen = name;
    screenViewport.scrollTo({ top: 0, behavior: options.instant || prefersReducedMotion.matches ? "auto" : "smooth" });
    if (options.updateUrl !== false) {
      const url = new URL(window.location.href);
      if (name === "home") url.searchParams.delete("screen");
      else url.searchParams.set("screen", name);
      history.replaceState(null, "", `${url.pathname}${url.search}${url.hash}`);
    }
    if (options.focus) {
      const heading = target.querySelector("h2");
      if (heading) {
        heading.tabIndex = -1;
        heading.focus({ preventScroll: true });
      }
    }
  }

  document.querySelectorAll("[data-screen]").forEach((button) => button.addEventListener("click", () => activateScreen(button.dataset.screen, { focus: true })));
  document.querySelectorAll("[data-screen-jump]").forEach((button) => button.addEventListener("click", () => activateScreen(button.dataset.screenJump, { focus: true })));
  railTabs.forEach((button, index) => button.addEventListener("keydown", (event) => {
    if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
    event.preventDefault();
    const direction = event.key === 'ArrowRight' ? 1 : -1;
    const next = railTabs[(index + direction + railTabs.length) % railTabs.length];
    next.focus();
    activateScreen(next.dataset.screen);
  }));

  const phoneShell = document.getElementById("phoneShell");
  document.getElementById("previewNudge")?.addEventListener("click", () => {
    phoneShell.focus({ preventScroll: true });
    phoneShell.classList.remove("nudged");
    void phoneShell.offsetWidth;
    phoneShell.classList.add("nudged");
    setTimeout(() => phoneShell.classList.remove("nudged"), 720);
  });

  const toast = document.getElementById("toast");
  const toastText = document.getElementById("toastText");
  let toastTimer;
  function showToast(message) {
    clearTimeout(toastTimer);
    toastText.textContent = message;
    toast.hidden = false;
    toastTimer = setTimeout(() => { toast.hidden = true; }, 2300);
  }

  const demoStateKey = "orbit-interactive-preview-v1";
  function readDemoState() {
    try {
      const value = JSON.parse(localStorage.getItem(demoStateKey) || "{}");
      return value && typeof value === "object" ? value : {};
    } catch {
      return {};
    }
  }
  const demoState = readDemoState();
  function persistDemoState() {
    try { localStorage.setItem(demoStateKey, JSON.stringify(demoState)); } catch { /* The demo still works without storage. */ }
  }

  const dailyBrief = document.getElementById("dailyBrief");
  const startDayButton = document.getElementById("startDayButton");
  if (demoState.dailyStarted) {
    dailyBrief.classList.add("started");
    startDayButton.querySelector("span").textContent = "Day in motion";
  }
  startDayButton.addEventListener("click", () => {
    const started = dailyBrief.classList.toggle("started");
    startDayButton.querySelector("span").textContent = started ? "Day in motion" : "Start my day";
    demoState.dailyStarted = started;
    persistDemoState();
    showToast(started ? "Your first focus block is ready" : "Daily flow paused");
  });

  const taskList = document.getElementById("taskList");
  const taskDoneCount = document.getElementById("taskDoneCount");
  const taskTotalCount = document.getElementById("taskTotalCount");
  const taskPercent = document.getElementById("taskPercent");
  const taskRing = document.querySelector(".task-ring");
  const homeTaskCount = document.getElementById("homeTaskCount");
  const homeTaskProgress = document.getElementById("homeTaskProgress");
  const homeTaskSummary = document.querySelector(".task-card > small");
  const moreTaskSummary = document.getElementById("moreTaskSummary");

  function createTaskRow(task) {
    const row = document.createElement("article");
    row.className = "task-row";
    row.dataset.task = "";
    row.dataset.taskId = task.id;
    row.innerHTML = `<button class="task-toggle"><span data-icon="check"></span></button><div><small>PERSONAL · DEMO</small><b></b><span><i data-icon="clock"></i> <span class="task-timing"></span></span></div><button class="task-more js-open-sheet" data-sheet="task"><span data-icon="more"></span></button>`;
    row.querySelector("b").textContent = task.title;
    row.querySelector(".task-timing").textContent = task.timing || "Today · Flexible";
    row.querySelector(".task-toggle").setAttribute("aria-label", `Mark ${task.title} complete`);
    row.querySelector(".task-more").setAttribute("aria-label", `Open ${task.title} details`);
    taskList.append(row);
    renderIcons(row);
    return row;
  }

  const customTasks = Array.isArray(demoState.customTasks) ? demoState.customTasks.filter((task) => task && typeof task.id === "string" && typeof task.title === "string").slice(0, 8) : [];
  customTasks.forEach(createTaskRow);
  demoState.customTasks = customTasks;

  if (Array.isArray(demoState.completedTaskIds)) {
    const completedIds = new Set(demoState.completedTaskIds);
    document.querySelectorAll("[data-task]").forEach((row) => row.classList.toggle("done", completedIds.has(row.dataset.taskId)));
  }

  function updateTaskProgress() {
    const taskRows = [...document.querySelectorAll("[data-task]")];
    const done = taskRows.filter((row) => row.classList.contains("done")).length;
    const left = taskRows.length - done;
    const percentage = taskRows.length ? Math.round((done / taskRows.length) * 100) : 0;
    taskDoneCount.textContent = done;
    taskTotalCount.textContent = taskRows.length;
    taskPercent.textContent = `${percentage}%`;
    taskRing.style.setProperty("--progress", `${percentage}%`);
    taskRing.setAttribute("aria-label", `${percentage} percent complete`);
    homeTaskCount.textContent = left;
    homeTaskProgress.style.width = `${percentage}%`;
    if (homeTaskSummary) homeTaskSummary.textContent = `${done} already done`;
    if (moreTaskSummary) moreTaskSummary.textContent = `${left} ${left === 1 ? "task" : "tasks"} left today`;
  }

  taskList.addEventListener("click", (event) => {
    const button = event.target.closest(".task-toggle");
    if (!button) return;
    const row = button.closest(".task-row");
    const completed = row.classList.toggle("done");
    row.classList.remove("just-completed");
    void row.offsetWidth;
    if (completed) row.classList.add("just-completed");
    const title = row.querySelector("b").textContent;
    button.setAttribute("aria-label", `Mark ${title} ${completed ? "incomplete" : "complete"}`);
    demoState.completedTaskIds = [...document.querySelectorAll("[data-task].done")].map((item) => item.dataset.taskId);
    persistDemoState();
    updateTaskProgress();
    showToast(completed ? "Nice—one less thing on your mind" : "Task moved back to today");
  });
  updateTaskProgress();

  dateButtons.forEach((button) => button.addEventListener("click", () => {
    dateButtons.forEach((item) => {
      item.classList.remove("active");
      item.setAttribute("aria-pressed", "false");
    });
    button.classList.add("active");
    button.setAttribute("aria-pressed", "true");
    showToast(button.querySelector("span").textContent === "TODAY" ? "Showing today" : `Showing ${button.querySelector("span").textContent.toLowerCase()}`);
  }));

  const jobFilterButtons = [...document.querySelectorAll("[data-job-filter]")];
  const jobList = document.getElementById("jobList");
  const jobActiveCount = document.getElementById("jobActiveCount");
  const homeJobCount = document.getElementById("homeJobCount");
  const moreJobSummary = document.getElementById("moreJobSummary");
  let activeJobFilter = "all";

  function createJobCard(job) {
    const card = document.createElement("article");
    card.className = "job-card";
    card.dataset.jobStatus = "active";
    card.dataset.jobId = job.id;
    card.innerHTML = `<button class="job-card-main js-open-sheet" data-sheet="custom-job"><span class="company-logo custom"></span><span class="job-copy"><small>NEW OPPORTUNITY · DEMO</small><b></b><span></span></span><span class="fit-score muted">NEW<small>FIT</small></span></button><div class="job-action"><span><i></i> Added to your preview</span><button class="js-open-sheet" data-sheet="custom-job">View details <i data-icon="arrow"></i></button></div>`;
    card.querySelector(".company-logo").textContent = job.company.slice(0, 1).toUpperCase();
    card.querySelector(".job-copy b").textContent = job.company;
    card.querySelector(".job-copy > span").textContent = `${job.role} · Demo`;
    card.querySelectorAll("[data-sheet='custom-job']").forEach((button) => {
      button.dataset.company = job.company;
      button.dataset.role = job.role;
      button.setAttribute("aria-label", `Open ${job.company} ${job.role} details`);
    });
    jobList.prepend(card);
    renderIcons(card);
    return card;
  }

  const customJobs = Array.isArray(demoState.customJobs) ? demoState.customJobs.filter((job) => job && typeof job.id === "string" && typeof job.company === "string" && typeof job.role === "string").slice(0, 6) : [];
  customJobs.slice().reverse().forEach(createJobCard);
  demoState.customJobs = customJobs;

  function getJobCards() { return [...document.querySelectorAll("[data-job-status]")]; }
  function updateJobCounts() {
    const cards = getJobCards();
    const totals = {
      all: cards.length,
      active: cards.filter((card) => card.dataset.jobStatus.split(" ").includes("active")).length,
      final: cards.filter((card) => card.dataset.jobStatus.split(" ").includes("final")).length
    };
    jobFilterButtons.forEach((button) => {
      const count = button.querySelector("span");
      if (count) count.textContent = String(totals[button.dataset.jobFilter] || 0);
    });
    jobActiveCount.textContent = totals.active;
    homeJobCount.textContent = `${totals.active} conversations moving`;
    moreJobSummary.textContent = `${totals.active} conversations moving`;
  }
  function filterJobs(filter) {
    activeJobFilter = filter;
    jobFilterButtons.forEach((button) => {
      const active = button.dataset.jobFilter === filter;
      button.classList.toggle("active", active);
      button.setAttribute("aria-selected", String(active));
    });
    getJobCards().forEach((card) => {
      const visible = filter === "all" || card.dataset.jobStatus.split(" ").includes(filter);
      card.classList.toggle("filter-hidden", !visible);
    });
  }
  jobFilterButtons.forEach((button, index) => {
    button.addEventListener("click", () => filterJobs(button.dataset.jobFilter));
    button.addEventListener("keydown", (event) => {
      if (!["ArrowLeft", "ArrowRight"].includes(event.key)) return;
      event.preventDefault();
      const direction = event.key === "ArrowRight" ? 1 : -1;
      const next = jobFilterButtons[(index + direction + jobFilterButtons.length) % jobFilterButtons.length];
      next.focus();
      filterJobs(next.dataset.jobFilter);
    });
  });
  updateJobCounts();
  filterJobs("all");

  const voiceLayer = document.getElementById("voiceLayer");
  const voiceVisual = document.getElementById("voiceVisual");
  const voiceHeading = document.getElementById("voiceHeading");
  const voiceResponse = document.getElementById("voiceResponse");
  const closeVoiceButton = document.getElementById("closeVoice");
  const voiceStop = document.getElementById("voiceStop");
  let voicePaused = false;
  let voiceTimer;

  function openVoice() {
    voiceLayer.hidden = false;
    voicePaused = false;
    voiceVisual.classList.remove("paused", "thinking");
    voiceHeading.innerHTML = "What should<br />we plan?";
    voiceResponse.textContent = "Choose a prompt to see how Orbit connects your day.";
    voiceStop.setAttribute("aria-label", "Pause assistant animation");
    setBackgroundInert(true, "voice");
    closeVoiceButton.focus();
  }
  function closeVoice() {
    clearTimeout(voiceTimer);
    voiceLayer.hidden = true;
    setBackgroundInert(false, "voice");
    document.getElementById("voiceButton").focus();
  }
  document.getElementById("voiceButton").addEventListener("click", openVoice);
  document.getElementById("askOrbit").addEventListener("click", openVoice);
  closeVoiceButton.addEventListener("click", closeVoice);
  voiceStop.addEventListener("click", () => {
    voicePaused = !voicePaused;
    voiceVisual.classList.toggle("paused", voicePaused);
    voiceResponse.textContent = voicePaused ? "Paused. Tap again when you’re ready." : "I’m listening again.";
    voiceStop.setAttribute("aria-label", voicePaused ? "Resume assistant animation" : "Pause assistant animation");
    showToast(voicePaused ? "Listening paused" : "Listening resumed");
  });

  const voiceReplies = {
    "Plan my afternoon": "You have a 45-minute portfolio block at 2, a recruiter reply before 4, and room for a walk at 5:30.",
    "Prep me for Google": "Let’s rehearse your portfolio story, three product tradeoffs, and the questions you want to ask the panel.",
    "What needs attention?": "Two things: reply to Maya before noon, and prepare for tomorrow’s Google final round. Everything else can wait."
  };
  document.querySelectorAll("[data-voice-prompt]").forEach((button) => button.addEventListener("click", () => {
    clearTimeout(voiceTimer);
    const prompt = button.dataset.voicePrompt;
    voiceHeading.textContent = `“${prompt}”`;
    voiceResponse.textContent = "Thinking across your Orbit…";
    voiceVisual.classList.add("thinking");
    voiceTimer = setTimeout(() => {
      voiceHeading.textContent = "Here’s the move.";
      voiceResponse.textContent = voiceReplies[prompt];
      voiceVisual.classList.remove("thinking");
    }, 760);
  }));

  const list = (items) => `<div class="sheet-list">${items.map((item) => `<div><span class="list-icon ${item.tone || ""}" data-icon="${item.icon}"></span><span><b>${item.title}</b><small>${item.detail}</small></span><strong>${item.value || ""}</strong></div>`).join("")}</div>`;
  const metrics = (items) => `<div class="sheet-metrics">${items.map((item) => `<div class="sheet-metric"><span>${item.label}</span><b>${item.value}</b><small>${item.detail}</small></div>`).join("")}</div>`;
  const hero = (tag, title, copy, score = "", scoreLabel = "") => `<div class="sheet-hero"><span>${tag}</span><h3>${title}</h3><p>${copy}</p>${score ? `<div class="sheet-score">${score}<small>${scoreLabel}</small></div>` : ""}</div>`;
  const section = (title, body) => `<section class="sheet-section"><h3>${title}</h3>${body}</section>`;
  const primary = (label, action = label) => `<button class="sheet-primary" data-sheet-action="${action}">${label}</button>`;
  const escapeMarkup = (value) => String(value).replace(/[&<>'"]/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[character]);

  const sheetLibrary = {
    streak: {
      eyebrow: "MOMENTUM", title: "7 day streak", icon: "spark",
      content: () => hero("YOU’RE ON A ROLL", "Seven days, gently done.", "Orbit counts progress—not perfection. You showed up in at least one meaningful way every day.", "7", "DAYS") + section("THIS WEEK", metrics([{label:"TASKS",value:"24",detail:"completed"},{label:"FOCUS",value:"4.2h",detail:"protected"},{label:"WINS",value:"9",detail:"celebrated"}])) + `<div class="sheet-note"><span data-icon="spark"></span>Keep the streak alive with one small win today. Your Google prep already counts.</div>` + primary("Choose today’s win")
    },
    profile: {
      eyebrow: "YOUR ORBIT", title: "Profile & settings", icon: "settings",
      content: () => `<div class="profile-card"><button class="avatar-button">HP<span></span></button><div><b>Het Patel</b><span>Indianapolis · Orbit member</span></div></div>` + section("YOUR SPACE", list([{icon:"settings",title:"Appearance & motion",detail:"Black · Playful motion",value:"›"},{icon:"inbox",tone:"coral",title:"Notifications",detail:"Only what needs attention",value:"›"},{icon:"link",tone:"sky",title:"Privacy & connections",detail:"You control every source",value:"›"}])) + primary("Done")
    },
    energy: {
      eyebrow: "DAILY ENERGY", title: "Ready for more", icon: "sun",
      content: () => hero("YOUR SIGNALS AGREE", "Energy is trending up.", "Good sleep and a lighter morning make this a strong day for focused creative work.", "82", "READY") + section("WHAT’S HELPING", list([{icon:"heart",tone:"coral",title:"Recovery",detail:"Above your 30-day baseline",value:"+12%"},{icon:"sun",tone:"lime",title:"Daylight",detail:"24 minutes before 9 AM",value:"Great"},{icon:"clock",tone:"sky",title:"Open focus time",detail:"Your clearest window",value:"2 PM"}])) + primary("Protect a focus block")
    },
    calendar: {
      eyebrow: "YOUR DAY", title: "Calendar", icon: "calendar",
      content: () => hero("4 EVENTS · 3H 15M", "A day with breathing room.", "Your afternoon is intentionally lighter after the portfolio review.") + section("TODAY", list([{icon:"video",tone:"coral",title:"Portfolio design review",detail:"10:30 AM · Google Meet",value:"45m"},{icon:"briefcase",title:"Google prep block",detail:"2:00 PM · Focus",value:"45m"},{icon:"heart",tone:"coral",title:"Evening walk",detail:"5:30 PM · Personal",value:"30m"}])) + primary("Add to calendar")
    },
    meeting: {
      eyebrow: "UP NEXT", title: "Portfolio design review", icon: "video",
      content: () => hero("STARTS IN 28 MIN", "You’re ready for this.", "The brief, Figma link and your last three notes are together below.") + section("MEETING KIT", list([{icon:"link",title:"Figma prototype",detail:"Latest version · updated yesterday",value:"Open"},{icon:"checklist",tone:"lime",title:"Talking points",detail:"Problem, insight, outcome",value:"3"},{icon:"brain",tone:"sky",title:"Orbit brief",detail:"90-second context summary",value:"Read"}])) + primary("Join Google Meet")
    },
    inbox: {
      eyebrow: "SMART INBOX", title: "Fresh news", icon: "inbox",
      content: () => hero("2 SAMPLE UPDATES", "The good kind of inbox.", "This preview shows how Orbit can surface only messages that change your plan.") + section("NEEDS YOU", list([{icon:"briefcase",title:"Google Recruiting",detail:"Final interview confirmation",value:"New"},{icon:"inbox",tone:"coral",title:"Maya Chen",detail:"Can you share availability?",value:"Reply"},{icon:"check-circle",tone:"lime",title:"Everything else",detail:"18 messages quietly sorted",value:"Done"}])) + primary("Open smart inbox")
    },
    health: {
      eyebrow: "HEALTH", title: "Today’s energy", icon: "heart",
      content: () => hero("SAMPLE HEALTH SIGNALS", "Ready for more.", "Recovery signals are above your baseline. A challenging workout fits before 6 PM.", "82", "READY") + section("TODAY AT A GLANCE", metrics([{label:"SLEEP",value:"7h 42",detail:"91 score"},{label:"MOVE",value:"620",detail:"kcal"},{label:"HRV",value:"58",detail:"+12%"}])) + `<div class="sheet-note"><span data-icon="heart"></span>Demo insight only. In the full app, you choose exactly which Apple Health signals Orbit can read.</div>` + primary("Explore health", "open-health")
    },
    finance: {
      eyebrow: "FINANCE", title: "Daily spending", icon: "wallet",
      content: () => hero("SAMPLE DAILY SPEND", "Comfortably on track.", "This demo models $48 of a $75 flexible daily target.", "64%", "USED") + section("TODAY", list([{icon:"wallet",title:"Lunch · Garden Table",detail:"Dining · 12:42 PM",value:"$18.40"},{icon:"link",tone:"sky",title:"Transit",detail:"Travel · 9:15 AM",value:"$6.00"},{icon:"check-circle",tone:"lime",title:"Weekly pace",detail:"$42 under your plan",value:"Good"}])) + primary("Open finance", "open-finance")
    },
    focus: {
      eyebrow: "FOCUS WITH ORBIT", title: "Google prep", icon: "bolt",
      content: () => hero("25 MINUTES", "One thing. Fully yours.", "Orbit will hold notifications, keep your prep notes close and let you know when the block ends.") + section("YOUR MINI PLAN", list([{icon:"briefcase",title:"Your opening story",detail:"Role, impact, why this team",value:"8m"},{icon:"brain",tone:"sky",title:"Product tradeoffs",detail:"Practice two examples",value:"10m"},{icon:"checklist",tone:"lime",title:"Questions for them",value:"7m",detail:"Choose your strongest three"}])) + primary("Start 25 minute focus", "start-focus")
    },
    "new-task": {
      eyebrow: "QUICK ADD", title: "New to do", icon: "plus",
      content: () => hero("CAPTURE IT", "Get it out of your head.", "Write naturally. Orbit can suggest timing and connect the task to a job, email or calendar event.") + `<label class="sheet-field"><span>Task</span><input class="sheet-input" data-field="task-title" maxlength="80" aria-label="Task title" placeholder="What do you want to do?" /></label><label class="sheet-field"><span>Timing</span><input class="sheet-input" data-field="task-timing" maxlength="48" aria-label="Task timing" placeholder="When? e.g. tomorrow at 2" /></label>` + primary("Add to my day", "add-task")
    },
    task: {
      eyebrow: "TO DO", title: "Task details", icon: "checklist",
      content: () => hero("TODAY", "Keep the next step tiny.", "Orbit grouped the context you need so this can move without another search.") + section("CONNECTED CONTEXT", list([{icon:"clock",title:"Timing",detail:"Today · flexible",value:"Edit"},{icon:"inbox",tone:"coral",title:"Source",detail:"Created from your inbox",value:"View"},{icon:"briefcase",title:"Related job",detail:"Google · Product Designer",value:"Open"}])) + primary("Mark complete")
    },
    "new-job": {
      eyebrow: "JOB TRACKER", title: "Add an opportunity", icon: "plus",
      content: () => hero("A NEW POSSIBILITY", "Let’s keep it moving.", "Add the basics now. Orbit can fill in the rest from a linked job post or recruiter email.") + `<label class="sheet-field"><span>Company</span><input class="sheet-input" data-field="job-company" maxlength="60" aria-label="Company" placeholder="Company" /></label><label class="sheet-field"><span>Role</span><input class="sheet-input" data-field="job-role" maxlength="80" aria-label="Role" placeholder="Role" /></label>` + primary("Add opportunity", "add-job")
    },
    "google-job": {
      eyebrow: "FINAL ROUND", title: "Google", icon: "briefcase",
      content: () => hero("TOMORROW · 2:00 PM", "Product Designer", "You’re at the final round. Your story, examples and interview details are ready in one place.", "92", "FIT") + section("NEXT BEST STEPS", list([{icon:"bolt",tone:"lime",title:"Run a 25-minute prep",detail:"Orbit’s recommended focus",value:"Start"},{icon:"video",tone:"coral",title:"Interview details",detail:"Tomorrow · Google Meet",value:"View"},{icon:"brain",tone:"sky",title:"Company brief",detail:"Role, team and recent notes",value:"Read"}])) + primary("Prep with Orbit")
    },
    "amazon-job": {
      eyebrow: "TEAM INTERVIEW", title: "Amazon", icon: "briefcase",
      content: () => hero("FOLLOW UP TODAY", "UX Designer", "The team interview landed well. A concise thank-you note keeps the conversation warm.", "86", "FIT") + section("ORBIT SUGGESTS", list([{icon:"inbox",tone:"coral",title:"Draft thank-you",detail:"Warm, direct and personal",value:"Draft"},{icon:"clock",tone:"sky",title:"Best send time",detail:"Before 3:30 PM today",value:"Today"},{icon:"checklist",tone:"lime",title:"Update tracker",detail:"Team interview complete",value:"Done"}])) + primary("Draft follow-up")
    },
    "notion-job": {
      eyebrow: "FINAL ROUND", title: "Notion", icon: "briefcase",
      content: () => hero("NEXT TUESDAY · 11:00 AM", "Product Designer", "Your portfolio has been shared and the final conversation is on the calendar.", "89", "FIT") + section("READY FOR YOU", list([{icon:"calendar",tone:"sky",title:"Final conversation",detail:"Next Tuesday · 11:00 AM",value:"45m"},{icon:"link",title:"Shared portfolio",detail:"Viewed yesterday",value:"Open"},{icon:"brain",tone:"lime",title:"Research notes",detail:"4 useful product signals",value:"Read"}])) + primary("Open opportunity")
    },
    "saved-job": {
      eyebrow: "SAVED ROLE", title: "Figma", icon: "briefcase",
      content: () => hero("SAVED 2 DAYS AGO", "Product Designer", "This role matches your product systems work, but the application closes soon.", "78", "FIT") + section("QUICK READ", list([{icon:"check-circle",tone:"lime",title:"Strong match",detail:"Design systems and prototyping",value:"2"},{icon:"clock",tone:"coral",title:"Application window",detail:"Closes in four days",value:"4d"},{icon:"link",tone:"sky",title:"Original post",detail:"Figma careers",value:"Open"}])) + primary("Start application")
    },
    automations: {
      eyebrow: "AUTOMATIONS", title: "Quietly working", icon: "bolt",
      content: () => hero("6 ROUTINES ACTIVE", "Less admin. More living.", "Orbit handles the repeatable parts and always asks before changing anything important.") + section("RUNNING NOW", list([{icon:"inbox",title:"Job email scan",detail:"Every 30 minutes",value:"On"},{icon:"calendar",tone:"sky",title:"Calendar to To Do",detail:"Only events you choose",value:"On"},{icon:"wallet",tone:"lime",title:"Weekly spending pulse",detail:"Friday at 5 PM",value:"On"}])) + primary("Create an automation")
    },
    memory: {
      eyebrow: "PERSONAL MEMORY", title: "Orbit remembers", icon: "brain",
      content: () => hero("12 APPROVED MEMORIES", "Helpful, never hidden.", "Only things you approve are remembered. Review or remove any memory whenever you want.") + section("RECENT", list([{icon:"brain",title:"Answer preference",detail:"Keep recommendations concise",value:"Edit"},{icon:"briefcase",tone:"sky",title:"Job preference",detail:"Hybrid or remote product roles",value:"Edit"},{icon:"heart",tone:"coral",title:"Routine",detail:"Prefer workouts before 6 PM",value:"Edit"}])) + primary("Review all memories")
    },
    connections: {
      eyebrow: "CONNECTED SERVICES", title: "Your sources", icon: "link",
      content: () => hero("PRIVATE BY DESIGN", "Connected, with boundaries.", "Orbit uses the minimum access each feature needs. You can disconnect a source at any time.") + section("CONNECTED", list([{icon:"inbox",title:"Gmail + Outlook",detail:"Read-only job and priority mail",value:"3"},{icon:"calendar",tone:"sky",title:"Calendars",detail:"Apple, Google and Outlook",value:"3"},{icon:"heart",tone:"coral",title:"Apple Health",detail:"Selected metrics only",value:"On"}])) + primary("Manage connections")
    }
  };

  const sheetBackdrop = document.getElementById("sheetBackdrop");
  const detailSheet = document.getElementById("detailSheet");
  const sheetEyebrow = document.getElementById("sheetEyebrow");
  const sheetTitle = document.getElementById("sheetTitle");
  const sheetBadge = document.getElementById("sheetBadge");
  const sheetContent = document.getElementById("sheetContent");
  const closeSheetButton = document.getElementById("closeSheet");
  const conceptRail = document.querySelector(".concept-rail");
  const appRegions = [conceptRail, document.querySelector(".app-header"), screenViewport, document.querySelector(".bottom-bar")].filter(Boolean);
  const openModalTypes = new Set();
  let lastFocused = null;

  function setBackgroundInert(enabled, type) {
    if (enabled) openModalTypes.add(type);
    else openModalTypes.delete(type);
    const shouldInert = openModalTypes.size > 0;
    appRegions.forEach((region) => { region.inert = shouldInert; });
    voiceLayer.inert = openModalTypes.has("sheet");
  }

  function openSheet(name, trigger) {
    const customCompany = trigger?.dataset.company || "New opportunity";
    const customRole = trigger?.dataset.role || "Role details";
    const data = name === "custom-job" ? {
      eyebrow: "DEMO OPPORTUNITY",
      title: customCompany,
      icon: "briefcase",
      content: () => hero("ADDED TO YOUR PREVIEW", escapeMarkup(customRole), "This sample opportunity now behaves like the rest of your Orbit job pipeline.") + section("NEXT BEST STEPS", list([{icon:"link",title:"Add the original role",detail:"Keep the source close",value:"Add"},{icon:"checklist",tone:"lime",title:"Choose a next action",detail:"Apply, research or reach out",value:"Plan"},{icon:"brain",tone:"sky",title:"Ask Orbit",detail:"Turn the role into a prep brief",value:"Ask"}])) + primary("Open job hunt", "open-jobs")
    } : sheetLibrary[name] || sheetLibrary.profile;
    lastFocused = trigger || document.activeElement;
    sheetEyebrow.textContent = data.eyebrow;
    sheetTitle.textContent = data.title;
    sheetBadge.dataset.icon = data.icon;
    sheetContent.innerHTML = data.content();
    renderIcons(detailSheet);
    sheetBackdrop.hidden = false;
    sheetBackdrop.setAttribute("aria-hidden", "false");
    setBackgroundInert(true, "sheet");
    detailSheet.scrollTop = 0;
    const firstInput = detailSheet.querySelector("input");
    (firstInput || closeSheetButton).focus();
  }
  function closeSheet() {
    sheetBackdrop.hidden = true;
    sheetBackdrop.setAttribute("aria-hidden", "true");
    setBackgroundInert(false, "sheet");
    if (lastFocused && document.contains(lastFocused)) lastFocused.focus();
  }

  const focusTimerLabel = document.querySelector(".focus-timer");
  let focusRemaining = 25 * 60;
  let focusTimerId = null;
  function paintFocusTimer() {
    const minutes = Math.floor(focusRemaining / 60);
    const seconds = String(focusRemaining % 60).padStart(2, "0");
    if (focusTimerLabel) focusTimerLabel.firstChild.textContent = `${minutes}:${seconds} `;
  }
  function toggleFocusTimer(forceStart = false) {
    if (focusTimerId && !forceStart) {
      clearInterval(focusTimerId);
      focusTimerId = null;
      showToast("Focus timer paused");
      return;
    }
    if (focusTimerId) clearInterval(focusTimerId);
    focusTimerId = setInterval(() => {
      focusRemaining -= 1;
      paintFocusTimer();
      if (focusRemaining <= 0) {
        clearInterval(focusTimerId);
        focusTimerId = null;
        focusRemaining = 25 * 60;
        paintFocusTimer();
        showToast("Focus block complete—beautiful work");
      }
    }, 1000);
    showToast("25 minute focus started");
  }

  document.addEventListener("click", (event) => {
    const opener = event.target.closest(".js-open-sheet");
    if (opener) {
      event.preventDefault();
      openSheet(opener.dataset.sheet, opener);
    }
    const action = event.target.closest("[data-sheet-action]");
    if (action) {
      const actionName = action.dataset.sheetAction;
      if (actionName === "add-task") {
        const title = detailSheet.querySelector("[data-field='task-title']")?.value.trim();
        const timing = detailSheet.querySelector("[data-field='task-timing']")?.value.trim();
        if (!title) {
          showToast("Add a task name first");
          detailSheet.querySelector("[data-field='task-title']")?.focus();
          return;
        }
        const task = { id: `custom-task-${Date.now()}`, title: title.slice(0, 80), timing: (timing || "Today · Flexible").slice(0, 48) };
        demoState.customTasks = [...(demoState.customTasks || []), task].slice(-8);
        createTaskRow(task);
        persistDemoState();
        updateTaskProgress();
        closeSheet();
        activateScreen("tasks", { focus: true });
        showToast("Task added to your day");
        return;
      }
      if (actionName === "add-job") {
        const company = detailSheet.querySelector("[data-field='job-company']")?.value.trim();
        const role = detailSheet.querySelector("[data-field='job-role']")?.value.trim();
        if (!company || !role) {
          showToast("Add both a company and role");
          detailSheet.querySelector(!company ? "[data-field='job-company']" : "[data-field='job-role']")?.focus();
          return;
        }
        const job = { id: `custom-job-${Date.now()}`, company: company.slice(0, 60), role: role.slice(0, 80) };
        demoState.customJobs = [...(demoState.customJobs || []), job].slice(-6);
        createJobCard(job);
        persistDemoState();
        updateJobCounts();
        filterJobs(activeJobFilter);
        closeSheet();
        activateScreen("jobs", { focus: true });
        showToast("Opportunity added to your preview");
        return;
      }
      if (actionName === "start-focus") {
        closeSheet();
        activateScreen("tasks", { focus: true });
        toggleFocusTimer(true);
        return;
      }
      const destinations = { "open-finance": "finance", "open-health": "health", "open-jobs": "jobs" };
      if (destinations[actionName]) {
        closeSheet();
        activateScreen(destinations[actionName], { focus: true });
        return;
      }
      const label = action.textContent.trim();
      closeSheet();
      showToast(label === "Done" ? "Settings saved" : `${label} is ready in this preview`);
    }
  });
  closeSheetButton.addEventListener("click", closeSheet);
  sheetBackdrop.addEventListener("click", (event) => { if (event.target === sheetBackdrop) closeSheet(); });

  document.querySelector(".js-job-prep").addEventListener("click", () => openSheet("focus", document.querySelector(".js-job-prep")));
  document.querySelector(".js-follow-up").addEventListener("click", () => {
    showToast("Follow-up draft is ready to review");
    setTimeout(() => openSheet("amazon-job", document.querySelector(".js-follow-up")), 260);
  });

  function trapFocus(event, container) {
    if (event.key !== "Tab") return;
    const focusable = [...container.querySelectorAll("button:not([disabled]), input:not([disabled]), textarea:not([disabled]), select:not([disabled]), [href], [tabindex='0']")].filter((node) => !node.hidden && !node.closest("[inert]"));
    if (!focusable.length) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  }

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      if (!sheetBackdrop.hidden) closeSheet();
      else if (!voiceLayer.hidden) closeVoice();
    }
    if (!sheetBackdrop.hidden) trapFocus(event, detailSheet);
    else if (!voiceLayer.hidden) trapFocus(event, voiceLayer);
  });

  const params = new URLSearchParams(window.location.search);
  const initialScreen = params.get("screen");
  activateScreen(screenOrder.includes(initialScreen) ? initialScreen : "home", { instant: true, updateUrl: false });
  const initialSheet = params.get("sheet");
  if (initialSheet) openSheet(initialSheet);
  else if (params.get("voice") === "1") openVoice();
})();
