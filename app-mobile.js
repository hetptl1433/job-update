const STATUSES = [
  "Interview Requested",
  "Interview Scheduled",
  "Interview Completed",
  "Assessment / Next Round",
  "Awaiting Response",
  "Offer Received",
  "Offer Accepted / Active",
  "Rejected",
  "Withdrawn",
  "Need Status Update"
];
const PRIORITIES = ["High", "Medium", "Low"];
const STAGES = ["Recruiter Screen", "One-way Video", "Hiring Manager Interview", "Final Interview", "Technical Assessment", "Offer / Onboarding", "Unknown"];
const FILTERS = ["All", "Active", "Offers", "Needs action", "Closed"];
const CLOSED = ["Rejected", "Withdrawn", "Offer Accepted / Active"];
const OFFERS = ["Offer Received", "Offer Accepted / Active"];

let interviews = [];
let filter = "All";
let search = "";
let editingId = null;
let updatedAt = null;
let toastTimer;

const $ = (id) => document.getElementById(id);
const form = $("editForm");

const iconPaths = {
  search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  download: '<path d="M12 3v12m0 0 4-4m-4 4-4-4"/><path d="M5 19h14"/>',
  upload: '<path d="M12 21V9m0 0 4 4m-4-4-4 4"/><path d="M5 5h14"/>',
  save: '<path d="M5 4h12l2 2v14H5z"/><path d="M8 4v6h8V4M8 20v-6h8v6"/>',
  edit: '<path d="m4 20 4.5-1 10-10-3.5-3.5-10 10z"/><path d="m13.5 6.5 3.5 3.5"/>',
  close: '<path d="m6 6 12 12M18 6 6 18"/>',
  external: '<path d="M14 4h6v6M20 4l-9 9"/><path d="M18 13v7H4V6h7"/>',
  trash: '<path d="M4 7h16M9 7V4h6v3M7 7l1 13h8l1-13"/>',
  lock: '<rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
  arrow: '<path d="m9 18 6-6-6-6"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  alert: '<path d="M12 4 3 20h18z"/><path d="M12 9v4m0 3h.01"/>'
};

function icon(name, size = 18) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${iconPaths[name] || ""}</svg>`;
}

function hydrateIcons() {
  document.querySelectorAll("[data-icon]").forEach((el) => {
    el.innerHTML = icon(el.dataset.icon);
  });
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>'"]/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    '"': "&quot;"
  })[char]);
}

function cloneSeed() {
  return JSON.parse(JSON.stringify(window.SEED_DATA || []));
}

function normalizeDate(value) {
  if (!value) return "";
  if (typeof value === "number" && window.XLSX) {
    const parsed = XLSX.SSF.parse_date_code(value);
    return parsed ? `${parsed.y}-${String(parsed.m).padStart(2, "0")}-${String(parsed.d).padStart(2, "0")}` : "";
  }
  const date = new Date(String(value));
  return Number.isNaN(date.getTime()) ? String(value).slice(0, 10) : date.toISOString().slice(0, 10);
}

function formatDate(value) {
  if (!value) return "";
  const [year, month, day] = String(value).slice(0, 10).split("-").map(Number);
  if (!year || !month || !day) return "";
  return new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric" }).format(new Date(year, month - 1, day));
}

function followUpState(item) {
  if (CLOSED.includes(item.status)) return "closed";
  if (!item.followUpDate) return "missing";
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const due = new Date(`${item.followUpDate}T00:00:00`);
  const difference = Math.round((due - today) / 86400000);
  if (difference < 0) return "overdue";
  if (difference === 0) return "today";
  if (difference <= 3) return "soon";
  return "upcoming";
}

function statusTone(status) {
  if (OFFERS.includes(status)) return "success";
  if (status === "Rejected" || status === "Withdrawn") return "danger";
  if (status === "Need Status Update") return "warning";
  return "info";
}

function followUpLabel(item) {
  const state = followUpState(item);
  if (state === "closed") return "Closed";
  if (state === "missing") return "Follow-up not set";
  if (state === "today") return "Follow up today";
  if (state === "overdue") return "Follow-up overdue";
  return `Follow up ${formatDate(item.followUpDate)}`;
}

function metrics() {
  const offers = interviews.filter((item) => OFFERS.includes(item.status)).length;
  const closed = interviews.filter((item) => CLOSED.includes(item.status)).length;
  const needsAction = interviews.filter((item) => item.status === "Need Status Update" || ["overdue", "today", "missing"].includes(followUpState(item))).length;
  const active = interviews.filter((item) => !CLOSED.includes(item.status) && item.status !== "Need Status Update").length;
  return { total: interviews.length, active, offers, needsAction, closed };
}

function setSync(state) {
  const indicator = $("syncIndicator");
  indicator.className = `sync-indicator ${state}`;
  $("syncText").textContent = state === "cloud" ? "Synced" : state === "saving" ? "Saving" : state === "error" ? "Sync issue" : "On device";
  $("saveButton").disabled = state === "saving";
  $("saveButton").innerHTML = `${icon("save")}${state === "saving" ? " Saving…" : " Save"}`;
  $("storageCopy").textContent = state === "cloud" ? "Cloud data is current." : "Showing saved or verified tracker data.";
}

function showToast(message) {
  clearTimeout(toastTimer);
  const toast = $("toast");
  toast.textContent = message;
  toast.hidden = false;
  toastTimer = setTimeout(() => {
    toast.hidden = true;
  }, 3200);
}

function render() {
  renderMetrics();
  renderFilters();
  renderCards();
}

function renderMetrics() {
  const summary = metrics();
  const cards = [
    ["Total", summary.total, "all companies"],
    ["Active", summary.active, "moving forward"],
    ["Offers", summary.offers, "received"],
    ["Action", summary.needsAction, "need attention"]
  ];
  $("metricGrid").innerHTML = cards.map(([label, value, detail]) => `
    <article class="metric-card">
      <span>${escapeHtml(label)}</span>
      <strong>${value}</strong>
      <small>${escapeHtml(detail)}</small>
    </article>
  `).join("");
}

function renderFilters() {
  $("filterTabs").innerHTML = FILTERS.map((name) => `
    <button class="tab ${filter === name ? "active" : ""}" data-filter="${escapeHtml(name)}">${escapeHtml(name)}</button>
  `).join("");
  document.querySelectorAll("[data-filter]").forEach((button) => {
    button.onclick = () => {
      filter = button.dataset.filter;
      render();
    };
  });
}

function filteredRows() {
  const query = search.trim().toLowerCase();
  const followOrder = { overdue: 0, today: 1, missing: 2, soon: 3, upcoming: 4, closed: 5 };
  const priorityOrder = { High: 0, Medium: 1, Low: 2 };
  return [...interviews]
    .filter((item) => {
      if (filter === "Active" && (CLOSED.includes(item.status) || item.status === "Need Status Update")) return false;
      if (filter === "Offers" && !OFFERS.includes(item.status)) return false;
      if (filter === "Needs action" && item.status !== "Need Status Update" && !["overdue", "today", "missing"].includes(followUpState(item))) return false;
      if (filter === "Closed" && !CLOSED.includes(item.status)) return false;
      if (!query) return true;
      return [item.company, item.role, item.status, item.stage, item.nextAction].join(" ").toLowerCase().includes(query);
    })
    .sort((a, b) => followOrder[followUpState(a)] - followOrder[followUpState(b)] || priorityOrder[a.priority] - priorityOrder[b.priority]);
}

function renderCards() {
  const rows = filteredRows();
  $("emptyState").hidden = rows.length > 0;
  $("trackerBody").innerHTML = rows.map((item) => {
    const tone = statusTone(item.status);
    const nextAction = item.nextAction && item.nextAction !== "Closed." ? item.nextAction : (CLOSED.includes(item.status) ? "No further action" : "Check the latest status");
    const dateText = item.interviewDate ? `Interview ${formatDate(item.interviewDate)}` : item.inviteDate ? `Invited ${formatDate(item.inviteDate)}` : "Date not set";
    return `
      <article class="company-card tone-${tone}">
        <button class="card-edit edit-entry" data-id="${item.id}" aria-label="Edit ${escapeHtml(item.company)}">${icon("edit", 17)}</button>
        <div class="company-heading">
          <span class="company-logo">${escapeHtml(item.company.slice(0, 2).toUpperCase())}</span>
          <div class="company-copy">
            <h2>${escapeHtml(item.company)}</h2>
            <p>${escapeHtml(item.role)}</p>
          </div>
        </div>
        <div class="status-line">
          <span class="status-pill status-${tone}">${escapeHtml(item.status)}</span>
          <span class="follow-pill follow-${followUpState(item)}">${escapeHtml(followUpLabel(item))}</span>
        </div>
        <div class="next-action">
          <span>Next</span>
          <p>${escapeHtml(nextAction)}</p>
        </div>
        <div class="card-meta">
          <span>${escapeHtml(item.stage || "Unknown stage")}</span>
          <span>${escapeHtml(dateText)}</span>
          <span class="priority-${String(item.priority || "Medium").toLowerCase()}">${escapeHtml(item.priority || "Medium")}</span>
        </div>
      </article>
    `;
  }).join("");
  document.querySelectorAll(".edit-entry").forEach((button) => {
    button.onclick = () => openModal(Number(button.dataset.id));
  });
}

function fillSelect(name, values) {
  form.elements[name].innerHTML = values.map((value) => `<option value="${escapeHtml(value)}">${escapeHtml(value)}</option>`).join("");
}

function openModal(id) {
  editingId = id;
  const existing = interviews.find((item) => Number(item.id) === Number(id));
  const item = existing ? { ...existing } : {
    id,
    company: "",
    role: "",
    stage: "Recruiter Screen",
    inviteDate: new Date().toISOString().slice(0, 10),
    interviewDate: "",
    status: "Interview Requested",
    priority: "Medium",
    nextAction: "",
    followUpDate: "",
    contact: "",
    mode: "",
    source: "",
    notes: ""
  };
  $("modalTitle").textContent = existing ? "Update status" : "Add company";
  Object.entries(item).forEach(([key, value]) => {
    if (form.elements[key]) form.elements[key].value = value || "";
  });
  $("deleteButton").hidden = !existing;
  $("sourceButton").hidden = !String(item.source).startsWith("http");
  $("sourceButton").href = String(item.source).startsWith("http") ? item.source : "#";
  $("modalBackdrop").hidden = false;
  document.body.style.overflow = "hidden";
}

function closeModal() {
  $("modalBackdrop").hidden = true;
  document.body.style.overflow = "";
  editingId = null;
}

function readForm() {
  const data = new FormData(form);
  return {
    id: editingId,
    company: String(data.get("company") || "").trim(),
    role: String(data.get("role") || "").trim(),
    stage: String(data.get("stage") || "Unknown"),
    inviteDate: String(data.get("inviteDate") || ""),
    interviewDate: String(data.get("interviewDate") || ""),
    status: String(data.get("status") || "Need Status Update"),
    priority: String(data.get("priority") || "Medium"),
    nextAction: String(data.get("nextAction") || "").trim(),
    followUpDate: String(data.get("followUpDate") || ""),
    contact: String(data.get("contact") || "").trim(),
    mode: String(data.get("mode") || "").trim(),
    source: String(data.get("source") || "").trim(),
    notes: String(data.get("notes") || "").trim()
  };
}

async function loadData(notify = false) {
  const password = $("adminPassword").value || sessionStorage.getItem("interview-admin-password") || "";
  if (password) {
    sessionStorage.setItem("interview-admin-password", password);
    $("adminPassword").value = password;
  }
  try {
    const headers = password ? { "x-admin-password": password } : {};
    const response = await fetch("/api/tracker", { cache: "no-store", headers });
    const payload = await response.json().catch(() => ({}));
    if (response.status === 401 || response.status === 503) {
      interviews = cloneSeed();
      setSync("local");
      if (notify) showToast(password ? "Password not accepted. Showing verified data." : "Showing verified tracker data.");
      render();
      return;
    }
    if (!response.ok) throw new Error(payload.error || "Cloud tracker unavailable");
    const cloudRows = Array.isArray(payload.data) ? payload.data : [];
    interviews = cloudRows.length ? cloudRows : cloneSeed();
    updatedAt = payload.updatedAt || null;
    setSync(payload.cloud ? "cloud" : "local");
    if (notify) showToast(payload.cloud ? "Cloud tracker loaded" : "Verified tracker loaded");
  } catch (error) {
    interviews = cloneSeed();
    setSync("local");
    if (notify) showToast("Showing verified tracker data");
  }
  updateLastSync();
  render();
}

function updateLastSync() {
  $("lastSync").textContent = updatedAt ? `Updated ${new Date(updatedAt).toLocaleString()}` : "";
}

async function saveOnline() {
  setSync("saving");
  const password = $("adminPassword").value;
  if (password) sessionStorage.setItem("interview-admin-password", password);
  try {
    const response = await fetch("/api/tracker", {
      method: "PUT",
      headers: { "Content-Type": "application/json", "x-admin-password": password },
      body: JSON.stringify(interviews)
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(payload.error || "Cloud save unavailable");
    updatedAt = payload.updatedAt;
    setSync("cloud");
    updateLastSync();
    showToast("Saved online");
  } catch (error) {
    setSync("local");
    showToast(`${error.message}. Your current view is still available.`);
  }
}

function exportExcel() {
  const rows = interviews.map((item) => ({
    ID: item.id,
    Company: item.company,
    Role: item.role,
    "Interview Stage": item.stage,
    "Invite Date": item.inviteDate,
    "Interview Date": item.interviewDate,
    "Current Status": item.status,
    Priority: item.priority,
    "Next Action": item.nextAction,
    "Follow-Up Date": item.followUpDate,
    "Contact / Recruiter": item.contact,
    "Mode / Location": item.mode,
    "Source / Evidence": item.source,
    Notes: item.notes
  }));
  if (window.XLSX) {
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, XLSX.utils.json_to_sheet(rows), "Interview Tracker");
    XLSX.writeFile(workbook, `Het_Interview_Tracker_${new Date().toISOString().slice(0, 10)}.xlsx`);
    showToast("Excel exported");
  } else {
    showToast("Excel library is still loading");
  }
}

async function importFile(file) {
  try {
    let mapped = [];
    if (file.name.toLowerCase().endsWith(".json")) {
      mapped = JSON.parse(await file.text());
    } else if (window.XLSX) {
      const workbook = XLSX.read(await file.arrayBuffer(), { type: "array" });
      const sheet = workbook.Sheets[workbook.SheetNames.includes("Interview Tracker") ? "Interview Tracker" : workbook.SheetNames[0]];
      const data = XLSX.utils.sheet_to_json(sheet, { defval: "" });
      mapped = data.map((row, index) => ({
        id: Number(row.ID || index + 1),
        company: String(row.Company || ""),
        role: String(row.Role || ""),
        stage: String(row["Interview Stage"] || "Unknown"),
        inviteDate: normalizeDate(row["Invite Date"]),
        interviewDate: normalizeDate(row["Interview Date"]),
        status: String(row["Current Status"] || "Need Status Update"),
        priority: String(row.Priority || "Medium"),
        nextAction: String(row["Next Action"] || ""),
        followUpDate: normalizeDate(row["Follow-Up Date"]),
        contact: String(row["Contact / Recruiter"] || ""),
        mode: String(row["Mode / Location"] || ""),
        source: String(row["Source / Evidence"] || ""),
        notes: String(row.Notes || "")
      }));
    } else {
      throw new Error("Excel library did not load");
    }
    mapped = mapped.filter((item) => item.company || item.role);
    if (!mapped.length) throw new Error("No company rows found");
    interviews = mapped;
    render();
    showToast(`Imported ${mapped.length} companies. Press Save to sync.`);
  } catch (error) {
    showToast(error.message || "Could not import file");
  }
}

fillSelect("stage", STAGES);
fillSelect("status", STATUSES);
fillSelect("priority", PRIORITIES);
hydrateIcons();

$("searchInput").addEventListener("input", (event) => {
  search = event.target.value;
  renderCards();
});
$("addButton").onclick = () => openModal(Math.max(0, ...interviews.map((item) => Number(item.id) || 0)) + 1);
$("importButton").onclick = () => $("fileInput").click();
$("fileInput").onchange = (event) => {
  const file = event.target.files[0];
  if (file) importFile(file);
  event.target.value = "";
};
$("exportButton").onclick = exportExcel;
$("saveButton").onclick = saveOnline;
$("closeModal").onclick = closeModal;
$("cancelButton").onclick = closeModal;
$("adminPassword").value = sessionStorage.getItem("interview-admin-password") || "";
$("adminPassword").addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    loadData(true);
  }
});
$("modalBackdrop").addEventListener("mousedown", (event) => {
  if (event.target === $("modalBackdrop")) closeModal();
});
form.addEventListener("submit", (event) => {
  event.preventDefault();
  const item = readForm();
  if (!item.company || !item.role) {
    showToast("Company and role are required");
    return;
  }
  const index = interviews.findIndex((entry) => Number(entry.id) === Number(item.id));
  if (index >= 0) interviews[index] = item;
  else interviews.push(item);
  closeModal();
  render();
  showToast("Status updated. Press Save to sync online.");
});
$("deleteButton").onclick = () => {
  const item = interviews.find((entry) => Number(entry.id) === Number(editingId));
  if (item && confirm(`Delete ${item.company}?`)) {
    interviews = interviews.filter((entry) => Number(entry.id) !== Number(editingId));
    closeModal();
    render();
    showToast("Company removed. Press Save to sync online.");
  }
};

loadData();