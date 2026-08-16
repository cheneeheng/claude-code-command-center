// ---- static DOM wiring (loaded last) ----
document.getElementById("btn-enable-all").addEventListener("click", () => bulkToggle(true));
document.getElementById("btn-disable-all").addEventListener("click", () => bulkToggle(false));

// Ask for the first load. This runs last, so messages.js has already registered the
// listener that receives the reply — the extension never posts `load` before that.
vscodeApi.postMessage({ type: "ready" });
