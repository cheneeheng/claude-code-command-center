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

// Scope-qualified element-id bundles (ITER_13/15/17). ids are built with CSS.escape
// on both sides so getElementById matches the literal (escaped) id.
function sectionInstallEls(scope, id) {
  const e = CSS.escape(id);
  return { btn: `btn-install-${scope}-${e}`, log: `log-${scope}-${e}`, err: `err-${scope}-${e}` };
}
function sectionUninstallEls(scope, id) {
  const e = CSS.escape(id);
  return { btn: `btn-uninstall-${scope}-${e}`, log: `log-${scope}-${e}`, err: `err-${scope}-${e}` };
}
function mpEls(id) {
  const e = CSS.escape(id);
  return { btn: `mp-btn-${e}`, log: `mp-log-${e}`, err: `mp-err-${e}` };
}
// Read the selected install scope at click time (CSS.escape applied at runtime so it
// matches the select's id attribute — never embed the escaped form into an onclick literal).
function mpScopeVal(id) {
  const sel = document.getElementById(`mp-scope-${CSS.escape(id)}`);
  return sel ? sel.value : "local";
}
