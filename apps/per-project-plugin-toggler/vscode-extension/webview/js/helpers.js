// ---- helpers ----
function showStatus(html) {
  const s = document.getElementById("status");
  s.innerHTML = html;
  s.style.display = "block";
  document.getElementById("error").style.display = "none";
}

function showError(msg) {
  const e = document.getElementById("error");
  e.textContent = msg;
  e.style.display = "block";
  document.getElementById("status").style.display = "none";
}

function esc(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// Scope-qualified element-id bundles (ITER_13/15/17). The plugin id goes in raw, because
// getElementById matches an id literally — it is not a selector. These once ran the id
// through CSS.escape, which was not just unnecessary: the renderers escaped the same way,
// so the backslashes CSS.escape adds ended up inside the rendered id="…" attribute, and an
// id carrying a double quote closed the attribute. The renderers now write these ids with
// esc(), which the browser decodes back to the raw id the lookups here use.
function sectionInstallEls(scope, id) {
  return { btn: `btn-install-${scope}-${id}`, log: `log-${scope}-${id}`, err: `err-${scope}-${id}` };
}
function sectionUninstallEls(scope, id) {
  return { btn: `btn-uninstall-${scope}-${id}`, log: `log-${scope}-${id}`, err: `err-${scope}-${id}` };
}
function mpEls(id) {
  return { btn: `mp-btn-${id}`, log: `mp-log-${id}`, err: `mp-err-${id}` };
}
// Read the selected install scope at click time, so the button carries only the plain id.
function mpScopeVal(id) {
  const sel = document.getElementById(`mp-scope-${id}`);
  return sel ? sel.value : "local";
}
