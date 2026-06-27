// ---- load ----
async function fetchPlugins() {
  const spinner = document.getElementById("loading-spinner");
  if (document.getElementById("plugin-sections").style.display !== "none") {
    spinner.style.display = "inline-block";
  }
  try {
    const res = await fetch("/api/plugins");
    const data = await res.json();
    if (!res.ok) {
      const pathInfo = data.path ? ` (${data.path})` : "";
      throw new Error(`${data.error || `HTTP ${res.status}`}${pathInfo}`);
    }
    const projectRoot = data.project_root || "";
    const folderName = projectRoot
      ? projectRoot.replace(/\\/g, "/").split("/").filter(Boolean).pop() || projectRoot
      : "";
    document.getElementById("project-name").textContent = folderName;
    document.getElementById("project-path").textContent = projectRoot;
    document.getElementById("project-path-input").value = projectRoot;
    document.getElementById("mock-notice").style.display = data.mock ? "flex" : "none";
    state.local = data.local || [];
    state.project = data.project || [];
    state.user = data.user || [];
    installedScopesMap = data.installedScopes || {};
    renderPlugins();
    if (installPanelOpen) renderInstallPanel();
  } catch (err) {
    document.getElementById("loading-spinner").style.display = "none";
    showError(`Failed to load plugins: ${err.message}`);
  }
}

// ---- fetch marketplace data ----
async function fetchMarketplace() {
  try {
    const res = await fetch("/api/marketplace");
    const data = await res.json();
    marketplaces = data.marketplaces || [];
    if (installPanelOpen) renderInstallPanel();
  } catch (_) {
    // Marketplace data is best-effort; don't surface errors here
  }
}

// ---- toggle (scope-aware, ITER_14) ----
async function toggle(id, enabled, el, scope) {
  el.disabled = true;
  const prev = !enabled;
  const p = (state[scope] || []).find((x) => x.id === id);
  if (p) p.enabled = enabled;
  const errEl = document.getElementById(`err-${scope}-${CSS.escape(id)}`);
  if (errEl) { errEl.textContent = ""; errEl.classList.remove("visible"); }
  try {
    const res = await fetch("/api/toggle", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id, enabled, scope }),
    });
    if (!res.ok) {
      const data = await res.json().catch(() => ({}));
      throw new Error(data.error || `HTTP ${res.status}`);
    }
  } catch (err) {
    if (p) p.enabled = prev;
    el.checked = prev;
    if (errEl) {
      errEl.textContent = `Toggle failed: ${err.message}`;
      errEl.classList.add("visible");
    } else {
      showError(`Toggle failed: ${err.message}`);
    }
  } finally {
    el.disabled = false;
  }
}

// ---- bulk (Local scope only — Project/User are higher blast radius) ----
async function bulkToggle(enabled) {
  const buttons = document.querySelectorAll(".bulk-actions button");
  buttons.forEach((b) => (b.disabled = true));
  for (const p of state.local) {
    if (p.enabled !== enabled) {
      const el = document.getElementById(`toggle-local-${CSS.escape(p.id)}`);
      if (el) await toggle(p.id, enabled, el, "local");
    }
  }
  buttons.forEach((b) => (b.disabled = false));
  renderPlugins();
}

async function triggerMarketplaceRefresh() {
  const btn   = document.getElementById("marketplace-refresh-btn");
  const logEl = document.getElementById("marketplace-refresh-log");
  if (!btn || !logEl) return;

  btn.disabled = true;
  btn.textContent = "↻ Refreshing…";
  logEl.textContent = "";
  logEl.classList.add("is-open");

  try {
    const res = await fetch("/api/marketplace-refresh", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({}),
    });

    if (!res.ok) {
      const data = await res.json();
      throw new Error(data.error || `HTTP ${res.status}`);
    }

    const reader  = res.body.getReader();
    const decoder = new TextDecoder();
    let   buffer  = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const parts = buffer.split("\n\n");
      buffer = parts.pop();

      for (const part of parts) {
        const dataLine = part.split("\n").find((l) => l.startsWith("data: "));
        if (!dataLine) continue;
        const payload = JSON.parse(dataLine.slice(6));

        if (payload.type === "line") {
          logEl.textContent += payload.text;
          logEl.scrollTop = logEl.scrollHeight;
        } else if (payload.type === "done") {
          if (!payload.ok) throw new Error(payload.error || "Refresh failed");
        }
      }
    }

    logEl.classList.remove("is-open");
    await fetchMarketplace();

  } catch (err) {
    logEl.textContent += `\nError: ${err.message}`;
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = "↻ Refresh";
    }
  }
}

// ---- streamed install / uninstall (scope-aware, row-agnostic via els) ----
async function _streamOp(endpoint, body, els, labels) {
  const btn   = els.btn ? document.getElementById(els.btn) : null;
  const errEl = els.err ? document.getElementById(els.err) : null;
  const logEl = els.log ? document.getElementById(els.log) : null;

  operationInProgress = true;
  if (btn)   { btn.textContent = labels.progress; btn.disabled = true; }
  if (errEl) { errEl.textContent = ""; errEl.classList.remove("visible"); }
  if (logEl) { logEl.textContent = ""; logEl.classList.add("is-open"); }

  try {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const data = await res.json().catch(() => ({}));
      throw new Error(data.error || `HTTP ${res.status}`);
    }

    const reader  = res.body.getReader();
    const decoder = new TextDecoder();
    let   buffer  = "";
    let   success = false;

    outer: while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const parts = buffer.split("\n\n");
      buffer = parts.pop();

      for (const part of parts) {
        const dataLine = part.split("\n").find((l) => l.startsWith("data: "));
        if (!dataLine) continue;
        const payload = JSON.parse(dataLine.slice(6));

        if (payload.type === "line") {
          if (logEl) { logEl.textContent += payload.text; logEl.scrollTop = logEl.scrollHeight; }
        } else if (payload.type === "done") {
          if (payload.ok) success = true;
          else throw new Error(payload.error || labels.failed);
          break outer;
        }
      }
    }
    reader.cancel().catch(() => {});

    if (success) {
      await new Promise((r) => setTimeout(r, 3000));
      operationInProgress = false;
      if (logEl) logEl.classList.remove("is-open");
      await Promise.all([fetchPlugins(), fetchMarketplace()]);
    }
  } catch (err) {
    operationInProgress = false;
    if (btn)   { btn.innerHTML = labels.idle; btn.disabled = false; }
    if (logEl) logEl.classList.remove("is-open");
    if (errEl) { errEl.textContent = `${labels.failed}: ${err.message}`; errEl.classList.add("visible"); }
  }
}

function installPlugin(id, scope, els) {
  return _streamOp("/api/install-stream", { id, scope }, els,
    { progress: "Installing…", idle: "Install &#8595;", failed: "Install failed" });
}

function uninstallPlugin(id, scope, els) {
  return _streamOp("/api/uninstall-stream", { id, scope }, els,
    { progress: "Uninstalling…", idle: "Uninstall", failed: "Uninstall failed" });
}
