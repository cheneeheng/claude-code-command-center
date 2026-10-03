// ---- install panel ----
let mpSearch = "";

function openInstallPanel() {
  installPanelOpen = true;
  if (!selectedMarketplace && marketplaces.length > 0) {
    selectedMarketplace = marketplaces[0].key;
  }
  renderInstallPanel();
  document.getElementById("install-panel").classList.add("is-open");
}

function closeInstallPanel() {
  installPanelOpen = false;
  document.getElementById("install-panel").classList.remove("is-open");
}

function renderInstallPanel() {
  const panel = document.getElementById("install-panel");

  if (marketplaces.length === 0) {
    panel.innerHTML = `
      <div class="install-panel-header">
        <span class="install-panel-title">Install plugin</span>
        <div style="display:flex;gap:8px;align-items:center;">
          <button class="marketplace-refresh-btn" id="marketplace-refresh-btn"
                  onclick="triggerMarketplaceRefresh()">&#8635; Refresh</button>
          <button class="install-panel-close" onclick="closeInstallPanel()">&#10005; Close</button>
        </div>
      </div>
      <div class="mp-install-log" id="marketplace-refresh-log"></div>
      <div class="status">No marketplaces configured. Add marketplaces via Claude Code before installing plugins.</div>`;
    return;
  }

  const options = marketplaces
    .map((m) => `<option value="${esc(m.key)}" ${m.key === selectedMarketplace ? "selected" : ""}>${esc(m.key)}</option>`)
    .join("");

  const mp = marketplaces.find((m) => m.key === selectedMarketplace);
  let pluginListHtml = "";
  if (mp) {
    if (mp.error) {
      pluginListHtml = `<div class="mp-install-error visible">${esc(mp.error)}</div>`;
    } else if (mp.plugins.length === 0) {
      pluginListHtml = `<div class="status">No plugins found in this marketplace.</div>`;
    } else {
      pluginListHtml = mp.plugins.map(renderMpPluginRow).join("");
    }
  }

  panel.innerHTML = `
    <div class="install-panel-header">
      <span class="install-panel-title">Install plugin</span>
      <div style="display:flex;gap:8px;align-items:center;">
        <button class="marketplace-refresh-btn" id="marketplace-refresh-btn"
                onclick="triggerMarketplaceRefresh()">&#8635; Refresh</button>
        <button class="install-panel-close" onclick="closeInstallPanel()">&#10005; Close</button>
      </div>
    </div>
    <div class="mp-install-log" id="marketplace-refresh-log"></div>
    <div class="marketplace-select-row">
      <span class="marketplace-select-label">Marketplace</span>
      <select class="marketplace-select" onchange="selectedMarketplace = this.value; mpSearch = ''; renderInstallPanel()">
        ${options}
      </select>
    </div>
    <input type="search" class="marketplace-search" id="marketplace-search"
           placeholder="Search plugins" value="${esc(mpSearch)}"
           oninput="mpSearch = this.value; applyMpSearch()">
    <div class="mp-plugin-list">${pluginListHtml}<div class="status" id="mp-search-empty" style="display:none">No matching plugins.</div></div>`;
  applyMpSearch();
}

// Hide rows instead of re-rendering so in-progress install logs and the input focus survive.
function applyMpSearch() {
  const q = mpSearch.trim().toLowerCase();
  let shown = 0;
  document.querySelectorAll("#install-panel .mp-plugin-row").forEach((row) => {
    const match = row.dataset.search.includes(q);
    row.style.display = match ? "" : "none";
    if (match) shown++;
  });
  const empty = document.getElementById("mp-search-empty");
  if (empty) empty.style.display = q && shown === 0 ? "" : "none";
}

function renderMpPluginRow(p) {
  const escId = esc(p.id);  // HTML attribute context
  const jsId = jsStr(p.id); // inline-handler (JS string) context
  const installedScopes = installedScopesMap[p.id] || [];
  const notInstalled = SCOPES.filter((s) => !installedScopes.includes(s));

  const tags = installedScopes
    .map((s) => `<span class="install-status">&#10003; Installed &middot; ${SCOPE_LABELS[s]}</span>`)
    .join(" ");

  const keywords = (p.keywords || [])
    .map((k) => `<span class="mp-keyword">${esc(k)}</span>`)
    .join("");

  let installControl = "";
  if (notInstalled.length > 0) {
    const opts = notInstalled
      .map((s, i) => `<option value="${s}" ${i === 0 ? "selected" : ""}>${SCOPE_LABELS[s]}</option>`)
      .join("");
    installControl = `
      <select class="mp-scope-select" id="mp-scope-${escId}">${opts}</select>
      <button class="mp-install-btn" id="mp-btn-${escId}"
              onclick="installPlugin('${jsId}', mpScopeVal('${jsId}'), mpEls('${jsId}'))">
        Install &#8595;
      </button>`;
  }

  return `
    <div class="mp-plugin-row" id="mp-row-${escId}"
         data-search="${esc([p.name, p.description, ...(p.keywords || [])].join(" ").toLowerCase())}">
      <div class="mp-plugin-main">
        <span class="mp-plugin-name">${esc(p.name)}</span>
        ${p.version ? `<span class="version-badge">v${esc(p.version)}</span>` : ""}
        ${tags}
      </div>
      <div class="mp-install-col">${installControl}</div>
      ${p.description ? `<div class="mp-plugin-description">${esc(p.description)}</div>` : ""}
      ${keywords ? `<div class="mp-keyword-list">${keywords}</div>` : ""}
      <div class="mp-install-error" id="mp-err-${escId}"></div>
      <div class="mp-install-log" id="mp-log-${escId}"></div>
    </div>`;
}
