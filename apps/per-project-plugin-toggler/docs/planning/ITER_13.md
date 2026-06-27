---
artifact: ITER_13
status: ready
created: 2026-06-06
scope: Reorganize plugins around Claude Code's three scopes (Local / Project / User) — read all three settings files and the install registry, show each plugin under every scope it participates in, with per-row enabled + installed state; badges rendered horizontally. Read/display only.
sections_changed: [01, 02, 04, 05]
sections_unchanged: [03]
depends_on: [SKELETON, ITER_01, ITER_02, ITER_03, ITER_04, ITER_05, ITER_06, ITER_07, ITER_08, ITER_09, ITER_10, ITER_11, ITER_12]
---

# ITER_13 · Three-scope model (Local / Project / User) — read & display

> **Supersedes** the earlier draft of ITER_13 (merge both project-level settings files into one effective `enabled` value, write only `settings.local.json`). That single-effective-value design is replaced: each scope is now its own section with its own enabled state read from its own settings file.

## §01 · Concept

The tool now mirrors Claude Code's three plugin scopes instead of the old Local/Global split:

- **Local** — personal, this project only (`.claude/settings.local.json`, install `scope: "local"`).
- **Project** — committed, shared with the team (`.claude/settings.json`, install `scope: "project"`).
- **User** — applies to all of your projects (`~/.claude/settings.json`, install `scope: "user"`). This replaces the former "Global" section.

A plugin appears under **every scope it participates in** — it can show in one, two, or all three sections at once. This iteration only **reads and displays** the three scopes correctly. Making each scope's toggle writable (item 2), installing per scope (items 3–4), and showing hooks (item 7) are separate later iterations.

---

## §02 · Architecture

### Data sources

```
~/.claude/plugins/installed_plugins.json   (read — install registry; scope ∈ local/project/user)
~/.claude/settings.json                     (read — USER-scope enabledPlugins)        ← new
<project>/.claude/settings.json             (read — PROJECT-scope enabledPlugins)     ← new
<project>/.claude/settings.local.json       (read+write — LOCAL-scope enabledPlugins) (existing)
        │
        ▼
  [ Plugin loader ] ──▶ three sections: local / project / user
        │
        ├──▶ [ HTML ]   server.py ◀──▶ index.html
        └──▶ [ VSCode ] extension.js ◀──▶ panel.html
```

> **`installed_plugins.json` schema:** the registry's structure (e.g. a `{ "version": 2, "plugins": { … } }` wrapper, per-entry `scope` of `local`/`project`/`user`, `projectPath`, `installPath`, `version`) is being handled separately. **Double-check that the rewritten loader consumes whatever shape the actual file now has** before building — the bucketing logic below assumes it can iterate install entries and read each entry's `scope`, `projectPath`, `installPath`, `version`, and `id`.

### Data model — revised, supersedes ITER_03 §02

A single **plugin row** shape, used in all three sections:

- `id` — `pluginname@marketplace`
- `name`, `marketplace` — split of `id`
- `version` — from the install entry at this scope; `""` if not installed at this scope
- `scope` — `"local" | "project" | "user"` (**replaces** `pluginScope: "local" | "global"`)
- `enabled` — boolean, from this scope's settings file `enabledPlugins[id]`, default `true` if absent. **Now present for every scope** — the ITER_03 rule that global plugins omit `enabled` and are always-on is removed.
- `installed` — boolean — **new** — is this plugin in `installed_plugins.json` at this scope? (Foundation for item 3.)
- `skills`, `agents` — from the install entry's `installPath`; **empty when `installed` is false** (no install path to read).
- (`hooks` — deferred to ITER_16.)

**Section membership rule.** For each scope `S` in `local`, `project`, `user`, a plugin id belongs to section `S` if **either**:

1. it has an install entry with `scope == S` (for `local`/`project`, `projectPath` must match `project_root` via `normalise_path`; `user` has no `projectPath` constraint), **or**
2. its id is a key in scope `S`'s settings-file `enabledPlugins`.

The two sources are **unioned** per scope. This is why a plugin enabled in a settings file but absent from the registry (item 3) still appears — flagged `installed: false`.

### API surface

`GET /api/plugins` response — **revised shape** (replaces ITER_03 `{ local, global }`):

```json
{
  "local":   [ { "id": "ceh-dev-tools@ceh-plugins", "name": "ceh-dev-tools", "marketplace": "ceh-plugins", "version": "1.1.0", "scope": "local", "enabled": true, "installed": true, "skills": [], "agents": [] } ],
  "project": [ { "id": "code-simplifier@anthropic", "name": "code-simplifier", "marketplace": "anthropic", "version": "", "scope": "project", "enabled": true, "installed": false, "skills": [], "agents": [] } ],
  "user":    [ { "id": "frontend-design@anthropic", "name": "frontend-design", "marketplace": "anthropic", "version": "2.0.1", "scope": "user", "enabled": true, "installed": true, "skills": [], "agents": [] } ],
  "project_root": "/path/to/project"
}
```

All other endpoints unchanged. `POST /api/toggle` is unchanged in behaviour and remains interactive **only for Local-section rows** this iteration (it already writes `settings.local.json`); Project/User toggle writes are deferred to ITER_14.

---

## §03 · Tech Stack
> Unchanged — no new dependencies (stdlib Python + vanilla JS / Node `fs`). See SKELETON § 03.

---

## §04 · Backend

### HTML version — `server.py`

**Settings loaders — three of them.** Keep `load_settings_local` (SKELETON §04). Add `load_settings_project(project_root)` reading `<project>/.claude/settings.json` and `load_settings_user()` reading `~/.claude/settings.json`. All three are mirrors with identical error handling; only the path differs.

```python
def load_settings_user():
    """Reads ~/.claude/settings.json (user-global). Mirror of load_settings_local; {} if missing/unparseable."""
    path = pathlib.Path.home() / ".claude" / "settings.json"
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return {}
```

`load_settings_project` is the same with `pathlib.Path(project_root) / ".claude" / "settings.json"`.

**`load_installed_plugins(project_root)` — rewrite to bucket by scope.** Returns `{ "local": [...], "project": [...], "user": [...] }`. Each entry is normalized to `{ "id", "version", "installPath" }`. Bucketing:

- `scope == "local"`  → `local` bucket **iff** `normalise_path(projectPath) == normalise_path(project_root)`
- `scope == "project"` → `project` bucket **iff** `normalise_path(projectPath) == normalise_path(project_root)`
- `scope == "user"`   → `user` bucket (no `projectPath` check)
- entries for other projects' local/project installs are skipped (they don't belong to this project)

> This corrects ITER_03, which only knew `local` vs not-local and would have mis-bucketed `scope: "project"` installs. Reuse the existing `normalise_path` helper for the Windows drive-letter case. Confirm the parse against the real `installed_plugins.json` shape (see §02 note).

**`build_sections(raw, settings)` — replaces `merge`.**

```python
def build_sections(raw, settings):
    """
    raw      = { "local": [...], "project": [...], "user": [...] } from load_installed_plugins()
               (each entry: {id, version, installPath}; projectPath already matched at load time)
    settings = { "local": {enabledPlugins}, "project": {enabledPlugins}, "user": {enabledPlugins} }
    Returns  { "local": [rows], "project": [rows], "user": [rows] }
    """
    def section(scope):
        installed_entries = {e["id"]: e for e in raw[scope]}
        enabled_map = settings[scope]
        ids = set(installed_entries) | set(enabled_map)   # union: registry ∪ this scope's settings
        rows = []
        for pid in sorted(ids):
            name, marketplace = pid.split("@", 1)
            entry = installed_entries.get(pid)
            installed = entry is not None
            install_path = entry.get("installPath", "") if installed else ""
            rows.append({
                "id": pid,
                "name": name,
                "marketplace": marketplace,
                "version": entry.get("version", "") if installed else "",
                "scope": scope,
                "enabled": enabled_map.get(pid, True),     # default: enabled
                "installed": installed,
                "skills": load_plugin_skills(install_path) if installed else [],
                "agents": load_plugin_agents(install_path) if installed else [],
            })
        return rows
    return {s: section(s) for s in ("local", "project", "user")}
```

**`GET /api/plugins` handler.**

```python
raw      = load_installed_plugins(self.server.project_root)
is_mock  = raw.pop("mock", False)
settings = {
    "local":   load_settings_local(self.server.project_root).get("enabledPlugins", {}),
    "project": load_settings_project(self.server.project_root).get("enabledPlugins", {}),
    "user":    load_settings_user().get("enabledPlugins", {}),
}
sections = build_sections(raw, settings)
payload  = {**sections, "project_root": self.server.project_root}
if is_mock:
    payload["mock"] = True
```

Update `_mock_plugins()` to return the three-bucket shape (`local`/`project`/`user`) so mock mode matches.

**File watcher — watch all three settings files.** Extend `_watched_paths()` (ITER_06 §04):

```python
def _watched_paths(self):
    return [
        pathlib.Path.home() / ".claude" / "plugins" / "installed_plugins.json",
        pathlib.Path.home() / ".claude" / "settings.json",                    # user   ← new
        pathlib.Path(self.project_root) / ".claude" / "settings.json",        # project ← new
        pathlib.Path(self.project_root) / ".claude" / "settings.local.json",  # local
    ]
```

> The `set-project` watcher reset (ITER_06 §04, `_watch_mtimes = {}`) re-seeds all paths next tick — the user path is constant, the two project paths follow the new root automatically. No extra change.

**`POST /api/toggle`** — behaviour unchanged (writes `settings.local.json`). Its guard still validates the requested id against the **local-scope** install set (now `raw["local"]` from the rewritten loader). Project/User toggle wiring is ITER_14.

### VSCode extension — `extension.js`

**Add `loadSettingsProject(projectRoot)` and `loadSettingsUser()`** — mirrors of `loadSettingsLocal` (SKELETON §04), reading `<project>/.claude/settings.json` and `path.join(os.homedir(), '.claude', 'settings.json')` respectively.

**Bucket installs by scope** in `loadInstalledPlugins` (same local/project/user rule as Python, same `projectPath` match), and add `buildSections(raw, settings)` mirroring the Python function. `_refresh` builds the three sections and posts them:

```js
const raw = loadInstalledPlugins(projectRoot);     // { local, project, user }
const settings = {
  local:   loadSettingsLocal(projectRoot).enabledPlugins   || {},
  project: loadSettingsProject(projectRoot).enabledPlugins || {},
  user:    loadSettingsUser().enabledPlugins               || {},
};
const sections = buildSections(raw, settings);     // { local, project, user }
// post { type: 'load', ...sections, project_root } to the webview
```

**Marketplace "installed" annotation — keep it working.** The annotation built in `_refresh` (ITER_04 §04 / ITER_12) must now union installed ids across all three sections instead of the old `local`/`global` sets:

```js
const installedIds = new Set();
for (const scope of ['local', 'project', 'user'])
  for (const p of sections[scope]) if (p.installed) installedIds.add(p.id);
```

> The marketplace **scope selector** (item 4) and acting on `installed: false` rows (item 3) are ITER_15. This change is only to stop the annotation breaking under the new shape.

**File watchers — add project and user settings.** Alongside the existing local `settingsWatcher` (ITER_06 §04):

```js
// Project settings.json — workspace-relative, like the local watcher
const projectSettingsWatcher = vscode.workspace.createFileSystemWatcher(
  new vscode.RelativePattern(vscode.workspace.workspaceFolders[0], '.claude/settings.json')
);
// User settings.json — absolute path glob (lives outside the workspace, like installed_plugins.json)
const userSettingsWatcher = vscode.workspace.createFileSystemWatcher(
  path.join(os.homedir(), '.claude', 'settings.json')
);
for (const w of [projectSettingsWatcher, userSettingsWatcher]) {
  w.onDidChange(onchange); w.onDidCreate(onchange); w.onDidDelete(onchange);
  context.subscriptions.push(w);
}
```

---

## §05 · Frontend

### Three sections (replaces the Local/Global split from ITER_03 §05)

Render three labelled sections in order: **Local plugins**, **Project plugins**, **User plugins**, each iterating its array from the `load` payload. Each section shows a muted empty state ("No plugins in this scope") when its array is empty. Loading/error states are unchanged — see ITER_03 §05.

### Row rendering

- **Enabled state.** Local-section rows keep the **existing interactive toggle** (writes `settings.local.json`, unchanged). Project- and User-section rows render `enabled` as a **read-only state indicator** this iteration; making them writable is ITER_14.
- **Installed state.** When `installed: false`, show a "Not installed" indicator and render no skills/agents (none are available without an install path). The Install action for these rows is ITER_15.
- **Element IDs must be scope-qualified.** Because the same plugin id can appear in up to three sections (item 5), every per-row element id must include the scope to avoid DOM collisions — e.g. `row-${scope}-${CSS.escape(id)}`, `toggle-${scope}-${CSS.escape(id)}`. Any handler that looks up a row element must pass `scope` too.

### Badges horizontal (item 6)

The marketplace and version badges currently stack vertically. Render them side by side. In `styles.css` (then `make sync-css`):

```css
.plugin-badges {            /* the container wrapping the marketplace + version badges */
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: 6px;
}
```

> Confirm the actual container class name in the current `index.html`/`panel.html` row markup and apply the flex-row there; the rule above assumes a `.plugin-badges` wrapper.

---

## Deferred

- **Per-scope toggle writes (item 2)** — make Project and User toggles writable, to the correct settings file (decision there: `claude plugin enable/disable --scope <scope>` vs. direct file write). → **ITER_14**
- **Scoped install (items 3 + 4)** — install an enabled-but-not-installed plugin at its scope, and a Local/Project/User selector on the marketplace install. Shared `claude plugin install --scope <scope>` backend. → **ITER_15**
- **Hooks display (item 7)** — parse `hooks.json` from each installed plugin's `installPath` into `(event, matcher, command)` rows and render as read-only structured text, grouped by event. → **ITER_16**
- **`installed_plugins.json` schema** — normalization handled separately; loader must be validated against the real file (see §02 note).
- **Changing an existing plugin's scope from the UI** (Claude Code feature request) — out of scope.
- **Smoke-test fixtures for the three-scope loader** (extends ITER_11) — recommended follow-up.
