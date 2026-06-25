// ---- static DOM wiring (loaded last) ----
document.getElementById("btn-enable-all").addEventListener("click", () => bulkToggle(true));
document.getElementById("btn-disable-all").addEventListener("click", () => bulkToggle(false));
