---
artifact: ITER_14
status: ready
created: 2026-06-06
scope: Make the enabled toggle writable in all three scopes — Local (unchanged), Project, and User — each writing enabledPlugins into its own settings file via read-modify-write. POST /api/toggle gains a required scope field.
sections_changed: [02, 04, 05]
sections_unchanged: [01, 03]
depends_on: [SKELETON, ITER_01, ITER_02, ITER_03, ITER_04, ITER_05, ITER_06, ITER_07, ITER_08, ITER_09, ITER_10, ITER_11, ITER_12, ITER_13]
---

# ITER_14 · Per-scope toggle writes

> Builds on ITER_13's three-scope read model. ITER_13 left Local interactive and Project/User as read-only state indicators; this iteration makes all three writable.

## §01 · Concept
> Unchanged — see ITER_13 § 01.

---

## §02 · Architecture

### Mechanism decision — direct file write (not the CLI)

The toggle writes `enabledPlugins[id] = <bool>` directly into the target scope's settings file, extending the approach the Local toggle already uses (ITER_03 §04). The alternative — shelling out to `claude plugin enable/disable <id> --scope <scope>` — is **rejected** here:

- A toggle is a single-bit flip; the CLI's extra behaviour (dependency resolution, cache management) is not wanted for a plain enable/disable and could write *additional* `enabledPlugins` entries unexpectedly.
- The Local toggle is already a synchronous, instant direct write; routing it through the install/uninstall SSE subprocess machinery would be heavier and slower for no benefit.
- Direct editing of `enabledPlugins` is a supported, first-class Claude Code workflow (it is read from the file on the next session).

> If a future iteration needs dependency-aware enabling, the CLI path can be revisited. Out of scope here.

### API surface

`POST /api/toggle` — **request body gains `scope`** (generalizes the local-only write from ITER_03 §02):

```json
{ "id": "code-simplifier@anthropic", "enabled": false, "scope": "project" }
```

- `scope` is **required**, one of `"local" | "project" | "user"`.
- Writes `enabledPlugins[id] = enabled` into that scope's settings file:
  - `local`   → `<project>/.claude/settings.local.json`
  - `project` → `<project>/.claude/settings.json`
  - `user`    → `~/.claude/settings.json`

Response: `{ "ok": true }`. Validation failures return `400 { "ok": false, "error": "..." }`.

The HTML server remains localhost-only (SKELETON §02) — that is the only access control on these writes; no new auth.

All other endpoints unchanged.

---

## §03 · Tech Stack
> Unchanged — see SKELETON § 03.

---

## §04 · Backend

### HTML version — `server.py`

**Settings savers — three, mirroring ITER_13's three loaders.** Keep `save_settings_local` (SKELETON §04). Add:

```python
def save_settings_project(project_root, settings):
    path = pathlib.Path(project_root) / ".claude" / "settings.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")

def save_settings_user(settings):
    path = pathlib.Path.home() / ".claude" / "settings.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
```

> **Other keys are preserved.** The handler loads the *full* settings dict (via ITER_13's `load_settings_*`), mutates only `enabledPlugins[id]`, and writes the whole dict back — so `permissions`, `env`, `extraKnownMarketplaces`, etc. survive. The file is re-emitted at 2-space indent (key order/whitespace not otherwise preserved), which Claude Code reads without issue.

**`POST /api/toggle` handler — rewrite to be scope-aware:**

```python
body    = self._read_json_body()
pid     = body.get("id", "")
enabled = body.get("enabled")
scope   = body.get("scope", "")

# --- Validation ---
if "@" not in pid:
    self._respond_json({"ok": False, "error": "Invalid plugin id format"}, status=400); return
if scope not in ("local", "project", "user"):
    self._respond_json({"ok": False, "error": "scope must be local, project, or user"}, status=400); return
if not isinstance(enabled, bool):
    self._respond_json({"ok": False, "error": "enabled must be a boolean"}, status=400); return

root = self.server.project_root

def read_scope(s):
    if s == "local":   return load_settings_local(root)
    if s == "project": return load_settings_project(root)
    return load_settings_user()

def write_scope(s, settings):
    if s == "local":     save_settings_local(root, settings)
    elif s == "project": save_settings_project(root, settings)
    else:                save_settings_user(settings)

# --- Guard: the id must belong to this scope's section (registry-at-scope ∪ settings-at-scope) ---
raw = load_installed_plugins(root)
installed_ids = {e["id"] for e in raw.get(scope, [])}
settings = read_scope(scope)
section_ids = installed_ids | set(settings.get("enabledPlugins", {}))
if pid not in section_ids:
    self._respond_json({"ok": False, "error": f"{pid} is not present in {scope} scope"}, status=400); return

# --- Write ---
settings.setdefault("enabledPlugins", {})[pid] = enabled
write_scope(scope, settings)
self._respond_json({"ok": True})
```

> **Guard allows not-installed rows.** A plugin that is in a scope's section only because of a settings entry (`installed: false`, from ITER_13) passes the guard via the `settings` half of the union, so its toggle works. Toggling it flips the settings flag only — it does **not** install the plugin (install is ITER_15).

> **`installed_plugins.json` schema:** as in ITER_13 §02, confirm the loader's bucketing against the real file shape.

### VSCode extension — `extension.js`

**Add `saveSettingsProject(projectRoot, settings)` and `saveSettingsUser(settings)`** — mirrors of `saveSettingsLocal` (SKELETON §04), writing to `<project>/.claude/settings.json` and `path.join(os.homedir(), '.claude', 'settings.json')`. Create parent dir if missing; `JSON.stringify(settings, null, 2)`.

**Toggle message handler — scope-aware.** The webview posts `{ type: 'toggle', id, enabled, scope }`. Generalize the existing handler (SKELETON §04):

```js
if (msg.type === 'toggle') {
  const { id, enabled, scope } = msg;

  // Confirmation — wording escalates with blast radius
  const where = scope === 'project'
    ? 'the shared .claude/settings.json (committed, affects your team)'
    : scope === 'user'
    ? 'your user settings (~/.claude/settings.json, affects all your projects)'
    : '.claude/settings.local.json (just you, this project)';
  const ok = await vscode.window.showWarningMessage(
    `Set "${id}" to ${enabled ? 'enabled' : 'disabled'} in ${where}?`,
    { modal: scope !== 'local' },     // modal for the higher-blast-radius scopes
    'Confirm'
  );
  if (ok !== 'Confirm') { this._refresh(webviewView.webview); return; }

  // read-modify-write the right file
  const load = { local: loadSettingsLocal, project: loadSettingsProject, user: loadSettingsUser };
  const save = { local: saveSettingsLocal, project: saveSettingsProject, user: saveSettingsUser };
  const settings = scope === 'user' ? load.user() : load[scope](projectRoot);
  settings.enabledPlugins = settings.enabledPlugins || {};
  settings.enabledPlugins[id] = enabled;
  if (scope === 'user') save.user(settings); else save[scope](projectRoot, settings);

  this._refresh(webviewView.webview);
}
```

> Local keeps a non-modal confirmation (matching prior behaviour); Project and User use a modal because they touch shared / cross-project state. The file watchers added in ITER_13 also catch the change and refresh, but the explicit `_refresh` keeps the UI immediate.

---

## §05 · Frontend

### Make all three toggles interactive

ITER_13 rendered Project/User `enabled` as read-only indicators. Render them as the same interactive toggle the Local section uses. The shared toggle function now takes `scope` and sends it:

- **HTML surface:** `POST /api/toggle` with `{ id, enabled, scope }`.
- **VSCode surface:** `postMessage({ type: 'toggle', id, enabled, scope })`.

Element ids are already scope-qualified (ITER_13 §05), so the same plugin in two sections has two independent toggles. The toggle handler must read `scope` from the row context (it is baked into the element id / passed at render time), not assume `local`.

After a successful toggle, refresh as today (HTML: re-fetch `/api/plugins`; VSCode: handled by `_refresh`). On a `400`, revert the toggle's visual state and surface the error inline (reuse the existing row error element).

### Not-installed rows

Their toggle is interactive and writes the scope's settings flag, but does not install the plugin — an Install affordance for `installed: false` rows is ITER_15. No special toggle handling is needed here beyond what the guard already permits.

---

## Deferred

- **Scoped install (items 3 + 4)** — install an enabled-but-not-installed plugin, and a Local/Project/User selector on the marketplace install. → **ITER_15**
- **Hooks display (item 7)** → **ITER_16**
- **CLI-based enable/disable** (`claude plugin enable/disable --scope`) — considered and rejected (see §02); revisit only if dependency-aware enabling is needed.
- **Smoke-test coverage** of `POST /api/toggle` across the three scopes (extends ITER_11) — recommended follow-up.
