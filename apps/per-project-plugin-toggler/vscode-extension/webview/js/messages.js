// ---- extension -> webview message handling ----
window.addEventListener("message", (event) => {
  const msg = event.data;
  if (msg.type === "load") {
    // Before the operationInProgress early return below, so the folder list stays current
    // while a streamed op holds the rest of the render.
    renderProjectCard(msg);
    document.getElementById("error").style.display = "none";
    state.local = (msg.plugins && msg.plugins.local) || [];
    state.project = (msg.plugins && msg.plugins.project) || [];
    state.user = (msg.plugins && msg.plugins.user) || [];
    installedScopesMap = msg.installedScopes || {};
    marketplaces = msg.marketplaces || [];
    // Restore selected marketplace if still valid
    if (selectedMarketplace && !marketplaces.find((m) => m.key === selectedMarketplace)) {
      selectedMarketplace = null;
    }
    // While a streamed install/uninstall is finishing, defer re-rendering so the
    // result log stays visible for its 3s window. opDone's completion timeout
    // re-renders from the state stored just above.
    if (operationInProgress) return;
    renderPlugins();
    if (installPanelOpen) renderInstallPanel();
  } else if (msg.type === "error") {
    // The card (and dropdown) stays up on error, so a broken folder never hides the way
    // back to a working one; the previous folder's rows are hidden so none stays clickable.
    if (msg.projectRoot) renderProjectCard(msg);
    showError(msg.message);
    document.getElementById("plugin-sections").style.display = "none";
    document.getElementById("bulk-actions").style.display = "none";
  } else if (msg.type === "marketplaceRefreshStart") {
    const btn   = document.getElementById("marketplace-refresh-btn");
    const logEl = document.getElementById("marketplace-refresh-log");
    if (btn)   { btn.disabled = true; btn.textContent = "↻ Refreshing…"; }
    if (logEl) { logEl.textContent = ""; logEl.classList.add("is-open"); }
  } else if (msg.type === "marketplaceRefreshLine") {
    const logEl = document.getElementById("marketplace-refresh-log");
    if (logEl) { logEl.textContent += event.data.text; logEl.scrollTop = logEl.scrollHeight; }
  } else if (msg.type === "marketplaceRefreshDone") {
    const btn   = document.getElementById("marketplace-refresh-btn");
    const logEl = document.getElementById("marketplace-refresh-log");
    if (btn)   { btn.disabled = false; btn.textContent = "↻ Refresh"; }
    if (!event.data.ok && logEl) {
      logEl.textContent += `\nError: ${event.data.error}`;
    } else if (logEl) {
      logEl.classList.remove("is-open");
    }
  } else if (msg.type === "installStart" || msg.type === "uninstallStart") {
    opStart(event.data.id);
  } else if (msg.type === "installLine" || msg.type === "uninstallLine") {
    opLine(event.data.id, event.data.text);
  } else if (msg.type === "installDone" || msg.type === "uninstallDone") {
    opDone(event.data.id, event.data.ok, event.data.error);
  }
});

// ---- project card ----
// One folder: the fixed name. Two or more (msg.projects): a dropdown of the workspace
// folders by name, with the selected folder's path under it either way.
function renderProjectCard(msg) {
  const projectRoot = msg.projectRoot || "";
  const projects = msg.projects || [];
  const nameEl = document.getElementById("project-name");
  const select = document.getElementById("project-select");
  if (projects.length > 1) {
    // Options built with textContent/value: folder names come from the user's
    // workspace file and must never reach innerHTML.
    select.replaceChildren(
      ...projects.map((p) => {
        const opt = document.createElement("option");
        opt.value = p.path;
        opt.textContent = p.name;
        return opt;
      })
    );
    select.value = projectRoot;
    select.disabled = operationInProgress;
    select.style.display = "";
    nameEl.style.display = "none";
  } else {
    const folderName = projectRoot
      ? projectRoot.replace(/\\/g, "/").split("/").filter(Boolean).pop() || projectRoot
      : "";
    nameEl.textContent = folderName;
    nameEl.style.display = "";
    select.style.display = "none";
  }
  document.getElementById("project-path").textContent = projectRoot;
  // Drop the inline display:none from panel.html; the stylesheet owns the value.
  document.getElementById("project-card").style.display = "";
}

// No switching while a streamed install/uninstall log is on screen.
function setProjectSelectEnabled(enabled) {
  document.getElementById("project-select").disabled = !enabled;
}

// ---- streamed-op UI helpers (shared by install + uninstall) ----
function opStart(id) {
  operationInProgress = true;
  setProjectSelectEnabled(false);
  const op = pendingOps[id];
  if (!op) return;
  const btn   = op.els.btn ? document.getElementById(op.els.btn) : null;
  const errEl = op.els.err ? document.getElementById(op.els.err) : null;
  const logEl = op.els.log ? document.getElementById(op.els.log) : null;
  if (btn)   { btn.textContent = op.progressLabel; btn.disabled = true; }
  if (errEl) { errEl.textContent = ""; errEl.classList.remove("visible"); }
  if (logEl) { logEl.textContent = ""; logEl.classList.add("is-open"); }
}

function opLine(id, text) {
  const op = pendingOps[id];
  const logEl = op && op.els.log ? document.getElementById(op.els.log) : null;
  if (logEl) { logEl.textContent += text; logEl.scrollTop = logEl.scrollHeight; }
}

function opDone(id, ok, error) {
  const op = pendingOps[id];
  if (ok) {
    setTimeout(() => {
      operationInProgress = false;
      setProjectSelectEnabled(true);
      delete pendingOps[id];
      // The { type: 'load' } that arrived at *Done time was deferred while
      // operationInProgress was true. Re-render now from that stored state so
      // section rows + install panel reset and the streamed log clears.
      renderPlugins();
      if (installPanelOpen) renderInstallPanel();
    }, 3000);
  } else {
    operationInProgress = false;
    setProjectSelectEnabled(true);
    if (op) {
      const btn   = op.els.btn ? document.getElementById(op.els.btn) : null;
      const errEl = op.els.err ? document.getElementById(op.els.err) : null;
      const logEl = op.els.log ? document.getElementById(op.els.log) : null;
      if (btn)   { btn.innerHTML = op.idleLabel; btn.disabled = false; }
      if (logEl) logEl.classList.remove("is-open");
      if (errEl) { errEl.textContent = `${op.failLabel}: ${error}`; errEl.classList.add("visible"); }
    }
    delete pendingOps[id];
  }
}
