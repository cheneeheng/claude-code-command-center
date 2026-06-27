// ---- install panel ----
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
      <select class="marketplace-select" onchange="selectedMarketplace = this.value; renderInstallPanel()">
        ${options}
      </select>
    </div>
    <div class="mp-plugin-list">${pluginListHtml}</div>`;
}

function renderMpPluginRow(p) {
  const escId = esc(p.id);
  const e = CSS.escape(p.id);
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
      <select class="mp-scope-select" id="mp-scope-${e}">${opts}</select>
      <button class="mp-install-btn" id="mp-btn-${e}"
              onclick="installPlugin('${escId}', mpScopeVal('${escId}'), mpEls('${escId}'))">
        Install &#8595;
      </button>`;
  }

  return `
    <div class="mp-plugin-row" id="mp-row-${e}">
      <div class="mp-plugin-main">
        <span class="mp-plugin-name">${esc(p.name)}</span>
        ${p.version ? `<span class="version-badge">v${esc(p.version)}</span>` : ""}
        ${tags}
      </div>
      <div class="mp-install-col">${installControl}</div>
      ${p.description ? `<div class="mp-plugin-description">${esc(p.description)}</div>` : ""}
      ${keywords ? `<div class="mp-keyword-list">${keywords}</div>` : ""}
      <div class="mp-install-error" id="mp-err-${e}"></div>
      <div class="mp-install-log" id="mp-log-${e}"></div>
    </div>`;
}
