---
artifact: ITER_15
status: ready
created: 2026-06-06
scope: Scoped install — add a scope to the install action so (item 4) marketplace installs can target Local/Project/User, and (item 3) an enabled-but-not-installed section row can be installed at its scope. Both drive `claude plugin install <id> --scope <scope>` through the existing install-stream path.
sections_changed: [02, 04, 05]
sections_unchanged: [01, 03]
depends_on: [SKELETON, ITER_01, ITER_02, ITER_03, ITER_04, ITER_05, ITER_06, ITER_07, ITER_08, ITER_09, ITER_10, ITER_11, ITER_12, ITER_13, ITER_14]
---

# ITER_15 · Scoped install (items 3 + 4)

> Builds on ITER_13 (`installed` flag per row, three sections) and ITER_07/ITER_12 (the install/uninstall SSE pattern). Install gains a scope; everything else about the streaming pattern is reused.

## §01 · Concept
> Unchanged — see ITER_13 § 01.

---

## §02 · Architecture

### Two entry points, one backend

Both call the existing `POST /api/install-stream` (ITER_07), now with a `scope`:

- **Item 4 — marketplace install:** the Install Panel offers a Local / Project / User choice; the chosen scope is sent.
- **Item 3 — install a not-installed section row:** a section row with `installed: false` (ITER_13) gets an Install button; its scope is **fixed to that row's section** (a Project-section row installs at `project`).

Install is delegated to the CLI, which owns updating both `installed_plugins.json` and the scope's `enabledPlugins`. The tool does not write those itself — it streams the CLI output and refreshes when done. After success, ITER_13's loader re-renders the row as `installed: true` with version/skills/agents, and ITER_14's toggle governs its enabled state.

### API surface

`POST /api/install-stream` — **request body gains `scope`** (was `{ id }` with a hardcoded `local` install, ITER_04/ITER_07):

```json
{ "id": "code-simplifier@anthropic", "scope": "project" }
```

- `scope` optional, one of `"local" | "project" | "user"`, **defaults to `"local"`** (preserves the prior behaviour for any existing caller).
- Runs `claude plugin install <id> --scope <scope>`; SSE stream shape unchanged (ITER_07).

> **Marketplace pre-check relaxed.** ITER_04 validated the marketplace key against `known_marketplaces.json` before installing. That pre-check is **dropped**: item-3 ids can reference marketplaces declared only in a settings file's `extraKnownMarketplaces`, which `known_marketplaces.json` would not list. Validation is now id-format + scope only; an unknown marketplace surfaces as a normal CLI error in the stream (same as uninstall, ITER_12 §04).

`POST /api/uninstall-stream` unchanged (ITER_12). The marketplace "installed" annotation stays the union-boolean from ITER_13 §04 (installed if installed at **any** scope).

---

## §03 · Tech Stack
> Unchanged — see SKELETON § 03.

---

## §04 · Backend

### HTML version — `server.py`

In the `/api/install-stream` handler (ITER_07 §04), make three changes:

```python
plugin_id = body.get("id", "")
scope     = body.get("scope", "local")          # ← new; default preserves prior behaviour

# --- Validation (replaces the known_marketplaces.json pre-check) ---
if "@" not in plugin_id:
    self._respond_json({"ok": False, "error": "Invalid plugin id format"}, status=400); return
if scope not in ("local", "project", "user"):
    self._respond_json({"ok": False, "error": "scope must be local, project, or user"}, status=400); return

# ... SSE scaffolding unchanged ...

proc = subprocess.Popen(
    ["claude", "plugin", "install", plugin_id, "--scope", scope],   # ← scope is now dynamic
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    cwd=self.server.project_root,
)
# ... line streaming + done event unchanged ...
```

> Confirm `claude plugin install --scope <local|project|user>` against the installed Claude Code version (same verification note as the `installed_plugins.json` schema in ITER_13 §02).

### VSCode extension — `extension.js`

`streamInstall` (ITER_07) gains a `scope` argument, passed into the spawn args:

```js
function streamInstall(pluginId, scope, projectRoot, onLine) {
  const proc = spawn('claude', ['plugin', 'install', pluginId, '--scope', scope], {
    cwd: projectRoot, stdio: ['ignore', 'pipe', 'pipe'],
  });
  // ... body identical to ITER_07 / the uninstall mirror in ITER_12 §04 ...
}
```

The `install` message handler passes the scope it receives from the webview (`{ type: 'install', id, scope }`) into `streamInstall`. Everything else (start/line/done message posting, `_refresh` on completion) is unchanged.

---

## §05 · Frontend

### `installPlugin` — make it scope-aware and row-agnostic

`installPlugin(id)` (ITER_04, extended for the toggle button in ITER_12) becomes `installPlugin(id, scope, els)`, where `els` names the row's button / log / error elements so the same function serves both entry points:

- **HTML surface:** `POST /api/install-stream` with `{ id, scope }`; stream into `els.log`, errors into `els.err`.
- **VSCode surface:** `postMessage({ type: 'install', id, scope })`.

The streaming/log/error handling itself is unchanged from ITER_04/ITER_07 — only the scope argument and the element lookup (now via `els`) change. On success, refresh as today.

### Item 4 — marketplace scope selector

In the marketplace row (ITER_12 §05), for the **not-installed** state, render a scope `<select>` before the Install button:

```html
<select class="mp-scope-select" id="mp-scope-${CSS.escape(p.id)}">
  <option value="local" selected>Local</option>
  <option value="project">Project</option>
  <option value="user">User</option>
</select>
<button class="mp-install-btn" id="mp-btn-${CSS.escape(p.id)}"
        onclick="installPlugin('${escapeHtml(p.id)}', document.getElementById('mp-scope-${CSS.escape(p.id)}').value, mpEls('${escapeHtml(p.id)}'))">
  Install ↓
</button>
```

`mpEls(id)` returns `{ btn: 'mp-btn-'+id, log: 'mp-log-'+id, err: 'mp-err-'+id }` (the existing marketplace element ids, ITER_07/ITER_12). The **installed** state is unchanged — it shows the Uninstall button from ITER_12 (installing the *same* plugin at an additional scope while already installed elsewhere is deferred — see Deferred).

### Item 3 — install a not-installed section row

For section rows with `installed: false` (ITER_13 §05), render an Install button whose scope is the row's section scope (no selector — scope is fixed):

```html
<button class="mp-install-btn" id="btn-install-${scope}-${CSS.escape(id)}"
        onclick="installPlugin('${escapeHtml(id)}','${scope}', sectionEls('${scope}','${escapeHtml(id)}'))">
  Install ↓
</button>
```

These rows must also include scope-qualified log and error elements (`log-${scope}-${id}`, `err-${scope}-${id}`) so the stream has somewhere to render; `sectionEls(scope, id)` returns those ids. Reuse the marketplace install-button styling (`.mp-install-btn`). On success, the refresh flips the row to `installed: true` with version/skills/agents populated.

> Element ids remain scope-qualified per ITER_13 §05, so the same plugin appearing in multiple sections has independent install controls.

---

## Deferred

- **Hooks display (item 7)** → **ITER_16**.
- **Installing an already-installed plugin at an additional scope** — the marketplace row shows Uninstall once a plugin is installed at any scope, so promoting/duplicating across scopes (the Claude Code multi-scope pain point, e.g. project→user) isn't reachable from the marketplace yet. A full per-scope install/uninstall matrix is a separate feature; deferred.
- **Per-scope uninstall from a section row** — uninstall stays in the marketplace panel (ITER_12); not requested for sections. Deferred.
- **Smoke-test coverage** of scoped install (extends ITER_11) — recommended follow-up.
