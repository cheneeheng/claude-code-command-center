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

// For values dropped into an inline onclick="fn('…')". That is a JS context nested in an
// HTML attribute, and the browser HTML-decodes the attribute before parsing the script —
// so esc() alone is not enough: it leaves ' untouched, and even &#39; would decode back to
// a quote and break out of the string literal. Escape for JS first (JSON.stringify covers
// backslashes, quotes and control chars), then esc() to keep the attribute intact.
function jsStr(s) {
  return esc(JSON.stringify(String(s)).slice(1, -1).replace(/'/g, "\\'"));
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
// Read the selected install scope at click time, so the onclick literal never has to carry
// anything but the plain id.
function mpScopeVal(id) {
  const sel = document.getElementById(`mp-scope-${id}`);
  return sel ? sel.value : "local";
}
