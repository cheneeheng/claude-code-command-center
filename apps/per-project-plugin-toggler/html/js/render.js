// ---- render (plugin sections) ----
function renderPlugins() {
  document.getElementById("loading-spinner").style.display = "none";
  const sections = document.getElementById("plugin-sections");
  const bulk = document.getElementById("bulk-actions");

  const total = SCOPES.reduce((n, s) => n + state[s].length, 0);
  if (total === 0) {
    showStatus("No plugins found for this project. Install plugins via Claude Code.");
    sections.style.display = "none";
    bulk.style.display = "none";
    return;
  }

  document.getElementById("status").style.display = "none";
  sections.style.display = "block";
  bulk.style.display = "flex";

  for (const scope of SCOPES) {
    document.getElementById(`${scope}-list`).innerHTML =
      state[scope].length
        ? state[scope].map((p) => sectionRowHtml(p, scope)).join("")
        : `<div class="section-empty">No plugins in this scope</div>`;
  }

  document.querySelectorAll(".toggle").forEach((el) => {
    el.addEventListener("change", (e) =>
      toggle(e.target.dataset.id, e.target.checked, e.target, e.target.dataset.scope)
    );
  });
}

function renderSkillsDisclosure(skills) {
  if (!skills || skills.length === 0) return "";
  const rows = skills.map((s) => `
    <div class="skill-row">
      <div class="skill-name">${esc(s.name)}</div>
      ${s.description ? `<div class="skill-description">${esc(s.description)}</div>` : ""}
    </div>`).join("");
  return `
    <div class="skills-disclosure">
      <button class="skills-toggle-btn" data-label="skill" onclick="toggleDisclosure(this)">
        ${skills.length} skill${skills.length !== 1 ? "s" : ""} &#9658;
      </button>
      <div class="skills-list">${rows}</div>
    </div>`;
}

function renderAgentsDisclosure(agents) {
  if (!agents || agents.length === 0) return "";
  const rows = agents.map((a) => `
    <div class="skill-row">
      <div class="skill-name">${esc(a.name)}</div>
      ${a.description ? `<div class="skill-description">${esc(a.description)}</div>` : ""}
    </div>`).join("");
  return `
    <div class="skills-disclosure">
      <button class="skills-toggle-btn" data-label="agent" onclick="toggleDisclosure(this)">
        ${agents.length} agent${agents.length !== 1 ? "s" : ""} &#9658;
      </button>
      <div class="skills-list">${rows}</div>
    </div>`;
}

function renderHooksDisclosure(hooks) {
  if (!hooks || hooks.length === 0) return "";
  const blocks = hooks.map((h) => {
    const matcher = h.matcher ? `<span class="hook-matcher">matcher: ${esc(h.matcher)}</span>` : "";
    const actions = (h.actions || []).map((a) =>
      `<div class="hook-action"><span class="hook-type">${esc(a.type)}</span> — <span class="hook-detail">${esc(a.detail)}</span></div>`
    ).join("");
    return `
      <div class="hook-block">
        <div class="hook-event">${esc(h.event)} ${matcher}</div>
        ${actions}
      </div>`;
  }).join("");
  return `
    <div class="skills-disclosure">
      <button class="skills-toggle-btn" data-label="hook" data-count="${hooks.length}" onclick="toggleDisclosure(this)">
        ${hooks.length} hook${hooks.length !== 1 ? "s" : ""} &#9658;
      </button>
      <div class="skills-list">${blocks}</div>
    </div>`;
}

function toggleDisclosure(btn) {
  const list = btn.nextElementSibling;
  const open = list.classList.toggle("is-open");
  const count = btn.dataset.count !== undefined
    ? btn.dataset.count
    : list.querySelectorAll(".skill-row").length;
  const label = btn.dataset.label || "skill";
  btn.textContent = `${count} ${label}${count != 1 ? "s" : ""} ${open ? "▾" : "▸"}`;
}

function sectionRowHtml(p, scope) {
  const escId = esc(p.id);
  const e = CSS.escape(p.id);
  const installed = p.installed !== false;

  const disclosures = installed
    ? renderSkillsDisclosure(p.skills) + renderAgentsDisclosure(p.agents) + renderHooksDisclosure(p.hooks)
    : "";

  const actionBtn = installed
    ? `<button class="mp-install-btn mp-install-btn--uninstall" id="btn-uninstall-${scope}-${e}"
               onclick="uninstallPlugin('${escId}','${scope}', sectionUninstallEls('${scope}','${escId}'))">Uninstall</button>`
    : `<button class="mp-install-btn" id="btn-install-${scope}-${e}"
               onclick="installPlugin('${escId}','${scope}', sectionInstallEls('${scope}','${escId}'))">Install &#8595;</button>`;

  return `
    <div class="plugin-row" id="row-${scope}-${e}" data-id="${escId}">
      <div class="plugin-row-main">
        <div class="plugin-info">
          <span class="plugin-name">${esc(p.name)}</span>
          <div class="plugin-badges">
            ${p.marketplace ? `<span class="marketplace-badge">@${esc(p.marketplace)}</span>` : ""}
            ${p.version ? `<span class="version-badge">v${esc(p.version)}</span>` : ""}
            ${!installed ? `<span class="not-installed-tag">Not installed</span>` : ""}
          </div>
          ${disclosures}
        </div>
        <div class="row-actions">
          <input type="checkbox" class="toggle" id="toggle-${scope}-${e}"
                 data-id="${escId}" data-scope="${scope}" ${p.enabled ? "checked" : ""} />
          ${actionBtn}
        </div>
      </div>
      <div class="mp-install-error" id="err-${scope}-${e}"></div>
      <div class="mp-install-log" id="log-${scope}-${e}"></div>
    </div>`;
}
