"use strict";

const PLANNING_DIR = ".agents_workspace/planning";
const state = { projects: [], selected: null, template: "" };

const $ = (id) => document.getElementById(id);
const enc = encodeURIComponent;

function notice(msg, isError) {
  const el = $("notice");
  el.textContent = msg || "";
  el.classList.toggle("error", !!isError);
}

function resolveTemplate(slug) {
  const path = `${PLANNING_DIR}/${slug}.md`;
  return state.template.includes("{path}")
    ? state.template.replaceAll("{path}", path)
    : state.template;
}

// The effective instruction for a plan: project override → defaults → constant, {path}
// filled, resolved server-side. Falls back to the global template if the fetch fails.
async function effectiveTemplate(project, slug) {
  try {
    const res = await fetch(
      `/api/instruction-template?project=${enc(project)}&slug=${enc(slug)}`
    ).then((r) => r.json());
    if (res.template) return res.template;
  } catch {
    /* fall through to the global template */
  }
  return resolveTemplate(slug);
}

// --- data ------------------------------------------------------------------

async function loadProjects() {
  try {
    const [pj, tpl] = await Promise.all([
      fetch("/api/projects").then((r) => r.json()),
      fetch("/api/instruction-template").then((r) => r.json()),
    ]);
    state.projects = pj.projects || [];
    state.template = tpl.template || "";
    renderTree();
  } catch (e) {
    $("tree").innerHTML = `<p class="placeholder">failed to load: ${e}</p>`;
  }
}

// --- tree ------------------------------------------------------------------

function renderTree() {
  const root = $("tree");
  root.innerHTML = "";
  if (!state.projects.length) {
    root.innerHTML =
      '<p class="placeholder">no projects — edit .docket.json and reload</p>';
    return;
  }
  for (const project of state.projects) {
    const box = document.createElement("div");
    box.className = "project";
    box.innerHTML =
      `<div class="project-name">${project.name}</div>` +
      `<div class="project-path">${project.path}</div>`;
    if (!project.plans.length) {
      box.insertAdjacentHTML("beforeend", '<div class="placeholder">no plans</div>');
    }
    for (const plan of project.plans) {
      box.appendChild(planRow(project, plan));
    }
    root.appendChild(box);
  }
  syncBatchButton();
}

function planRow(project, plan) {
  const row = document.createElement("div");
  row.className = "plan-row";
  row.dataset.project = project.name;
  row.dataset.slug = plan.slug;

  const cb = document.createElement("input");
  cb.type = "checkbox";
  cb.disabled = plan.status !== "ready";
  cb.title = cb.disabled
    ? "only ready plans can be batch-implemented"
    : "select for batch implement";
  cb.addEventListener("click", (e) => e.stopPropagation());
  cb.addEventListener("change", syncBatchButton);

  const badge = document.createElement("span");
  badge.className = `badge ${plan.status}`;
  badge.textContent = plan.status;

  const label = document.createElement("span");
  label.textContent = plan.title;

  row.append(cb, badge, label);
  row.addEventListener("click", () => selectPlan(project.name, plan.slug, row));
  if (state.selected &&
      state.selected.project === project.name && state.selected.slug === plan.slug) {
    row.classList.add("selected");
  }
  return row;
}

function checkedItems() {
  return [...document.querySelectorAll(".plan-row")]
    .filter((r) => r.querySelector("input").checked)
    .map((r) => ({ project: r.dataset.project, slug: r.dataset.slug }));
}

function syncBatchButton() {
  $("implement-selected").disabled = checkedItems().length === 0;
}

// --- plan view -------------------------------------------------------------

async function selectPlan(project, slug, row) {
  document.querySelectorAll(".plan-row.selected").forEach((r) => r.classList.remove("selected"));
  if (row) row.classList.add("selected");
  state.selected = { project, slug };
  try {
    const plan = await fetch(`/api/plan?project=${enc(project)}&slug=${enc(slug)}`)
      .then((r) => r.json());
    if (plan.error) throw new Error(plan.error);
    state.selected = plan;
    renderPlan(plan);
  } catch (e) {
    notice(`plan load failed: ${e.message}`, true);
  }
}

function renderPlan(plan) {
  $("plan-title").textContent = plan.title;
  $("plan-title").classList.remove("placeholder");
  const st = $("plan-status");
  st.textContent = plan.status;
  st.className = `badge ${plan.status}`;
  $("plan-body").textContent = plan.body;
  $("plan-body").classList.remove("placeholder");

  const controls = $("plan-controls");
  controls.hidden = false;
  $("btn-implement").disabled = plan.status !== "ready";
  $("btn-implement").title =
    plan.status === "ready"
      ? ""
      : plan.status === "running"
        ? "running — stop it first"
        : "already implemented — reopen to run again";
  $("btn-runmyself").disabled = plan.status === "running";
  $("btn-mark").hidden = plan.status !== "ready";
  $("btn-reopen").hidden = plan.status !== "implemented";
}

async function refreshSelected() {
  await loadProjects();
  if (state.selected) {
    await selectPlan(state.selected.project, state.selected.slug, null);
  }
}

// --- manual controls -------------------------------------------------------

async function runMyself() {
  const { project, slug, body } = state.selected;
  const res = await fetch(`/api/runcmd?project=${enc(project)}&slug=${enc(slug)}`)
    .then((r) => r.json());
  if (res.error) return notice(res.error, true);
  appendLog("run-myself", `$ ${res.cmd}`, null);
  try {
    await navigator.clipboard.writeText(body);
    notice("plan body copied to clipboard");
  } catch {
    notice("clipboard unavailable — copy the command shown in the log");
  }
}

async function manual(endpoint) {
  const { project, slug } = state.selected;
  const res = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ project, slug }),
  }).then((r) => r.json());
  if (res.error) return notice(res.error, true);
  notice("");
  await refreshSelected();
}

// --- headless run + streaming ----------------------------------------------

async function implementOne() {
  const { project, slug } = state.selected;
  const def = await effectiveTemplate(project, slug);
  const instruction = window.prompt("Instruction (names the plan file):", def);
  if (instruction === null) return;
  await submitBatch([{ project, slug, instruction }]);
  await refreshSelected();
}

async function implementSelected() {
  const items = checkedItems();
  if (!items.length) return;
  for (const item of items) {
    const def = await effectiveTemplate(item.project, item.slug);
    const ins = window.prompt(`Instruction for ${item.project}/${item.slug}:`, def);
    if (ins === null) return; // cancel whole batch
    item.instruction = ins;
  }
  await submitBatch(items);
  await refreshSelected();
}

async function submitBatch(items) {
  const res = await fetch("/api/implement", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ items }),
  }).then((r) => r.json());
  if (res.error) return notice(res.error, true);
  notice("");
  $("btn-stop").hidden = false;
  $("logs").querySelector(".placeholder")?.remove();
  for (const run of res.runs) openStream(run);
}

const activeRuns = new Map(); // run_id -> { source, slug }

function openStream(run) {
  const label = `${run.project}/${run.slug}`;
  const source = new EventSource(`/api/stream?run_id=${enc(run.run_id)}`);
  activeRuns.set(run.run_id, { source, label });

  source.onmessage = (e) => appendLog(run.run_id, e.data, label);
  source.addEventListener("end", (e) => {
    appendLog(run.run_id, `— ${e.data} —`, label, true);
    source.close();
    activeRuns.delete(run.run_id);
    if (activeRuns.size === 0) {
      $("btn-stop").hidden = true;
      refreshSelected();
    }
  });
  source.onerror = () => {
    appendLog(run.run_id, "stream interrupted — refresh to see final status", label, true);
  };
}

function appendLog(runId, text, label, isEnd) {
  const logs = $("logs");
  let block = document.getElementById(`log-${runId}`);
  if (!block) {
    block = document.createElement("div");
    block.className = "run-log";
    block.id = `log-${runId}`;
    block.innerHTML = `<h4>${label || runId}</h4><pre></pre>`;
    logs.appendChild(block);
  }
  const pre = block.querySelector("pre");
  const line = document.createElement("span");
  if (isEnd) line.className = "end";
  line.textContent = text + "\n";
  pre.appendChild(line);
  logs.scrollTop = logs.scrollHeight;
}

async function stopActive() {
  for (const [runId] of activeRuns) {
    await fetch("/api/stop", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ run_id: runId }),
    });
  }
}

// --- theme -----------------------------------------------------------------

// Inline SVG icons (no external asset — the CSP blocks remote fetches). The
// button shows the icon of the theme it switches TO: a sun when dark, moon when light.
const SUN_ICON =
  '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor"' +
  ' stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
  '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4' +
  'M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>';
const MOON_ICON =
  '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor"' +
  ' stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
  '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>';

// Active theme = explicit data-theme if set, else the OS preference.
function activeTheme() {
  return (
    document.documentElement.dataset.theme ||
    (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light")
  );
}

function syncThemeButton() {
  const dark = activeTheme() === "dark";
  const btn = $("theme-toggle");
  btn.innerHTML = dark ? SUN_ICON : MOON_ICON;
  btn.setAttribute("aria-label", dark ? "Switch to light theme" : "Switch to dark theme");
  btn.title = btn.getAttribute("aria-label");
}

function toggleTheme() {
  const next = activeTheme() === "dark" ? "light" : "dark";
  document.documentElement.dataset.theme = next;
  localStorage.setItem("docket-theme", next);
  syncThemeButton();
}

// --- wire up ---------------------------------------------------------------

$("theme-toggle").addEventListener("click", toggleTheme);
syncThemeButton();

$("btn-runmyself").addEventListener("click", runMyself);
$("btn-mark").addEventListener("click", () => manual("/api/implemented"));
$("btn-reopen").addEventListener("click", () => manual("/api/reopen"));
$("btn-implement").addEventListener("click", implementOne);
$("implement-selected").addEventListener("click", implementSelected);
$("btn-stop").addEventListener("click", stopActive);

loadProjects();
