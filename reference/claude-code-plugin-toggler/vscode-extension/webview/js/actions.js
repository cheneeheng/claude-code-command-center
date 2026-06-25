// ---- install / uninstall actions (VSCode) ----
// Record els + labels so streamed-op messages (which carry only id) reach the right row,
// then hand off to the extension which drives the CLI and posts back start/line/done.
function installPlugin(id, scope, els) {
  pendingOps[id] = { els, progressLabel: "Installing…", idleLabel: "Install &#8595;", failLabel: "Install failed" };
  vscodeApi.postMessage({ type: "install", id, scope });
}

function uninstallPlugin(id, scope, els) {
  pendingOps[id] = { els, progressLabel: "Uninstalling…", idleLabel: "Uninstall", failLabel: "Uninstall failed" };
  vscodeApi.postMessage({ type: "uninstall", id, scope });
}

function triggerMarketplaceRefresh() {
  vscodeApi.postMessage({ type: "marketplaceRefresh" });
}

// ---- bulk (Local scope only — Project/User are higher blast radius) ----
function bulkToggle(enabled) {
  for (const p of state.local) {
    if (p.enabled !== enabled) {
      p.enabled = enabled;
      vscodeApi.postMessage({ type: "toggle", id: p.id, enabled, scope: "local" });
    }
  }
  renderPlugins();
}
