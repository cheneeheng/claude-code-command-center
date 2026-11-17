// ---- static DOM wiring (loaded last) ----
document.getElementById("btn-enable-all").addEventListener("click", () => bulkToggle(true));
document.getElementById("btn-disable-all").addEventListener("click", () => bulkToggle(false));

// Project switch (multi-root workspace). The previous folder's rows are hidden first, so
// none can be toggled while the extension switches; the next load/error replaces the
// loading text.
document.getElementById("project-select").addEventListener("change", (e) => {
  document.getElementById("plugin-sections").style.display = "none";
  document.getElementById("bulk-actions").style.display = "none";
  showStatus("Loading plugins…");
  vscodeApi.postMessage({ type: "selectProject", path: e.target.value });
});

// Ask for the first load. This runs last, so messages.js has already registered the
// listener that receives the reply — the extension never posts `load` before that.
vscodeApi.postMessage({ type: "ready" });
