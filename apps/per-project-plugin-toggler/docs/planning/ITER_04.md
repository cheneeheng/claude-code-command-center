---
artifact: ITER_04
status: ready
created: 2026-05-15
scope: Plugin install flow — browse available plugins from known marketplaces, install locally via CLI command
sections_changed: [02, 04, 05]
sections_unchanged: [01, 03]
---

## §01 · Concept
> Unchanged — see SKELETON.md §01

---

## §02 · Architecture

### Component diagram (updated)

```
~/.claude/plugins/installed_plugins.json   (read only — installed state)
~/.claude/plugins/known_marketplaces.json  (read only — marketplace registry)
        │
        ▼
  [ Plugin loader + Marketplace loader ]
        │
        ├──▶ [ HTML version ]
        │       server.py (HTTP) ◀──▶ index.html (browser)
        │       start.sh / start.bat / start.ps1
        │
        └──▶ [ VSCode version ]
                extension.js ◀──▶ panel.html (Webview sidebar)
                        │
                        ▼
        ./.claude/settings.local.json      (read + write — enabled state)
        subprocess: claude plugin install  (write — install new plugins)
```

### Data model (updated)

**MarketplacePlugin** — new entity, represents a plugin available in a marketplace but not necessarily installed:
- `name` — string, e.g. `"ceh-agent-coding-contract"`
- `marketplace` — string, the marketplace key, e.g. `"ceh-plugins"`
- `id` — string, derived as `"<name>@<marketplace>"`, e.g. `"ceh-agent-coding-contract@ceh-plugins"`
- `description` — string, from `plugins[].description` in `marketplace.json`
- `version` — string, from `plugins[].version` in `marketplace.json`
- `author` — string, from `plugins[].author.name` in `marketplace.json`, empty string if absent
- `keywords` — `string[]`, from `plugins[].keywords` in `marketplace.json`, empty array if absent
- `installed` — boolean, derived: true if the plugin `id` appears in `installed_plugins.json` for the current project (local or global)
- `installedScope` — `"local"` | `"global"` | `null` — null if not installed

**Marketplace** — new entity:
- `key` — string, top-level key from `known_marketplaces.json`, e.g. `"ceh-plugins"`
- `installLocation` — string, absolute path, e.g. `"C:\\Users\\Chen\\.claude\\plugins\\marketplaces\\ceh-plugins"`
- `marketplaceJsonPath` — string, derived: `<installLocation>/.claude-plugin/marketplace.json`
- `lastUpdated` — string, ISO timestamp from `known_marketplaces.json`
- `plugins` — `MarketplacePlugin[]`, loaded from `marketplaceJsonPath`; empty array if file is missing or unreadable

**InstalledPlugin, Skill, Agent** — unchanged from ITER_03.md §02.

### API surface (HTML version — additions only)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/marketplace` | Returns all known marketplaces with their available plugins |
| `POST` | `/api/install` | Runs `claude plugin install <id> --scope local` as a subprocess |

All prior endpoints unchanged — see ITER_03.md §02.

---

`GET /api/marketplace` response shape:
```json
{
  "marketplaces": [
    {
      "key": "ceh-plugins",
      "lastUpdated": "2026-05-14T14:18:52.841Z",
      "plugins": [
        {
          "name": "ceh-agent-coding-contract",
          "marketplace": "ceh-plugins",
          "id": "ceh-agent-coding-contract@ceh-plugins",
          "description": "CEH agent coding contract: interactive vs autonomous modes.",
          "version": "2.2.0",
          "author": "cheneeheng",
          "keywords": ["agent", "coding-contract", "workflow"],
          "installed": true,
          "installedScope": "local"
        }
      ]
    }
  ]
}
```

Error if `known_marketplaces.json` is missing:
```json
{ "marketplaces": [], "error": "known_marketplaces.json not found" }
```

A marketplace whose `marketplace.json` file is missing or unreadable is included with `"plugins": []` and an `"error"` key on the marketplace object:
```json
{
  "key": "ceh-plugins",
  "lastUpdated": "...",
  "plugins": [],
  "error": "marketplace.json not found at <path>"
}
```

---

`POST /api/install` request body:
```json
{ "id": "ceh-agent-coding-contract@ceh-plugins" }
```

`POST /api/install` response — success:
```json
{ "ok": true, "id": "ceh-agent-coding-contract@ceh-plugins" }
```

`POST /api/install` response — failure:
```json
{ "ok": false, "error": "claude plugin install exited with code 1: <stderr output>" }
```

> **Install is always `--scope local`.** This UI only installs into the current project. Global install is out of scope.

> **Guard:** before spawning the subprocess, validate that `id` matches the pattern `<name>@<marketplace>` and that the marketplace key exists in `known_marketplaces.json`. Respond `400` if either check fails.

---

## §03 · Tech Stack
> Unchanged — see ITER_01.md §03

New subprocess dependency: `subprocess` (Python stdlib, already available). `claude` CLI must be on `PATH` for install to work. The backend does not verify `claude` is installed at startup — the error surfaces at install time.

---

## §04 · Backend

### File structure (updated)

```
html/
├── server.py        ← updated
├── index.html       ← updated
├── styles.css       ← updated
├── start.sh
├── start.bat
└── start.ps1

vscode-extension/
├── package.json
├── extension.js     ← updated
├── icon.svg
└── webview/
    ├── panel.html   ← updated
    └── styles.css   ← updated (keep in sync with html/styles.css)
```

### `server.py` changes

**New constants:**

```python
PLUGINS_BASE     = pathlib.Path.home() / ".claude" / "plugins"
MARKETPLACES_JSON = PLUGINS_BASE / "known_marketplaces.json"
```

---

**New helper: `load_known_marketplaces()`**

```python
def load_known_marketplaces():
    """
    Reads ~/.claude/plugins/known_marketplaces.json.
    Returns list of { "key", "installLocation", "lastUpdated" } dicts.
    Returns [] if file is missing.
    """
    if not MARKETPLACES_JSON.exists():
        return []
    raw = json.loads(MARKETPLACES_JSON.read_text(encoding="utf-8"))
    result = []
    for key, info in raw.items():
        result.append({
            "key": key,
            "installLocation": info.get("installLocation", ""),
            "lastUpdated": info.get("lastUpdated", ""),
        })
    return result
```

---

**New helper: `load_marketplace_plugins(marketplace_key, install_location)`**

```python
def load_marketplace_plugins(marketplace_key, install_location):
    """
    Reads <install_location>/.claude-plugin/marketplace.json.
    Returns (plugins_list, error_string_or_None).
    plugins_list entries: { "name", "description", "version", "author", "keywords" }
    """
    if not install_location:
        return [], "installLocation is empty"
    mp_json = pathlib.Path(install_location) / ".claude-plugin" / "marketplace.json"
    if not mp_json.exists():
        return [], f"marketplace.json not found at {mp_json}"
    try:
        raw = json.loads(mp_json.read_text(encoding="utf-8"))
    except Exception as e:
        return [], f"Failed to parse marketplace.json: {e}"

    plugins = []
    for p in raw.get("plugins", []):
        plugins.append({
            "name": p.get("name", ""),
            "description": p.get("description", ""),
            "version": p.get("version", ""),
            "author": (p.get("author") or {}).get("name", ""),
            "keywords": p.get("keywords", []),
        })
    return plugins, None
```

---

**New helper: `build_marketplace_response(project_root)`**

```python
def build_marketplace_response(project_root):
    """
    Combines known_marketplaces.json with each marketplace's marketplace.json.
    Annotates each plugin with installed/installedScope derived from
    installed_plugins.json for the current project_root.
    """
    # Build installed-id lookup for fast annotation
    raw_installed = load_installed_plugins(project_root)
    installed_local  = {e["id"] for e in raw_installed["local"]}
    installed_global = {e["id"] for e in raw_installed["global"]}

    marketplaces_meta = load_known_marketplaces()
    if not marketplaces_meta:
        return {"marketplaces": [], "error": "known_marketplaces.json not found"}

    result = []
    for m in marketplaces_meta:
        plugins_raw, err = load_marketplace_plugins(m["key"], m["installLocation"])
        entry = {
            "key": m["key"],
            "lastUpdated": m["lastUpdated"],
        }
        if err:
            entry["plugins"] = []
            entry["error"] = err
        else:
            annotated = []
            for p in plugins_raw:
                pid = f"{p['name']}@{m['key']}"
                if pid in installed_local:
                    installed, scope = True, "local"
                elif pid in installed_global:
                    installed, scope = True, "global"
                else:
                    installed, scope = False, None
                annotated.append({
                    **p,
                    "marketplace": m["key"],
                    "id": pid,
                    "installed": installed,
                    "installedScope": scope,
                })
            entry["plugins"] = annotated
        result.append(entry)

    return {"marketplaces": result}
```

---

**New handler: `GET /api/marketplace`**

```python
# Inside RequestHandler.do_GET, add branch:
elif parsed.path == "/api/marketplace":
    payload = build_marketplace_response(self.server.project_root)
    self._respond_json(payload)
```

---

**New handler: `POST /api/install`**

```python
# Inside RequestHandler.do_POST, add branch:
elif parsed.path == "/api/install":
    body = self._read_json_body()
    plugin_id = body.get("id", "")

    # Validate format
    if "@" not in plugin_id:
        self._respond_json({"ok": False, "error": "Invalid plugin id format"}, status=400)
        return

    marketplace_key = plugin_id.split("@", 1)[1]

    # Validate marketplace exists
    known = load_known_marketplaces()
    known_keys = {m["key"] for m in known}
    if marketplace_key not in known_keys:
        self._respond_json({"ok": False, "error": f"Unknown marketplace: {marketplace_key}"}, status=400)
        return

    # Run install
    try:
        result = subprocess.run(
            ["claude", "plugin", "install", plugin_id, "--scope", "local"],
            capture_output=True,
            text=True,
            timeout=60,
            cwd=self.server.project_root,
        )
    except FileNotFoundError:
        self._respond_json({"ok": False, "error": "'claude' CLI not found on PATH"}, status=500)
        return
    except subprocess.TimeoutExpired:
        self._respond_json({"ok": False, "error": "Install timed out after 60 seconds"}, status=500)
        return

    if result.returncode != 0:
        stderr = result.stderr.strip() or result.stdout.strip()
        self._respond_json({"ok": False, "error": f"Exit code {result.returncode}: {stderr}"}, status=500)
        return

    self._respond_json({"ok": True, "id": plugin_id})
```

> **`subprocess` import:** add `import subprocess` at the top of `server.py` alongside existing stdlib imports.

> **`cwd` for subprocess:** pass `project_root` as the working directory so that `claude plugin install --scope local` writes into the correct project's settings.

---

### `extension.js` changes

**New helper: `loadKnownMarketplaces()`**

```js
function loadKnownMarketplaces() {
  const mp = path.join(os.homedir(), '.claude', 'plugins', 'known_marketplaces.json');
  if (!fs.existsSync(mp)) return [];
  const raw = JSON.parse(fs.readFileSync(mp, 'utf8'));
  return Object.entries(raw).map(([key, info]) => ({
    key,
    installLocation: info.installLocation || '',
    lastUpdated: info.lastUpdated || '',
  }));
}
```

---

**New helper: `loadMarketplacePlugins(marketplaceKey, installLocation)`**

```js
function loadMarketplacePlugins(marketplaceKey, installLocation) {
  if (!installLocation) return { plugins: [], error: 'installLocation is empty' };
  const mpJson = path.join(installLocation, '.claude-plugin', 'marketplace.json');
  if (!fs.existsSync(mpJson)) return { plugins: [], error: `marketplace.json not found at ${mpJson}` };
  try {
    const raw = JSON.parse(fs.readFileSync(mpJson, 'utf8'));
    const plugins = (raw.plugins || []).map(p => ({
      name: p.name || '',
      description: p.description || '',
      version: p.version || '',
      author: (p.author || {}).name || '',
      keywords: p.keywords || [],
    }));
    return { plugins, error: null };
  } catch (e) {
    return { plugins: [], error: `Failed to parse marketplace.json: ${e.message}` };
  }
}
```

---

**`_refresh(webview)` — extended** to include marketplace data in the `{ type: 'load' }` message:

```js
// Inside _refresh(webview):
const raw = loadInstalledPlugins(projectRoot);
const enabledMap = loadSettingsLocal(projectRoot).enabledPlugins || {};
const plugins = buildPluginList(raw, enabledMap);

// Build installed-id set for annotation
const installedLocal  = new Set(raw.local.map(e => e.id));
const installedGlobal = new Set(raw.global.map(e => e.id));

const marketplacesMeta = loadKnownMarketplaces();
const marketplaces = marketplacesMeta.map(m => {
  const { plugins: mpPlugins, error } = loadMarketplacePlugins(m.key, m.installLocation);
  const entry = { key: m.key, lastUpdated: m.lastUpdated };
  if (error) {
    entry.plugins = [];
    entry.error = error;
  } else {
    entry.plugins = mpPlugins.map(p => {
      const pid = `${p.name}@${m.key}`;
      let installed = false, installedScope = null;
      if (installedLocal.has(pid))  { installed = true; installedScope = 'local'; }
      else if (installedGlobal.has(pid)) { installed = true; installedScope = 'global'; }
      return { ...p, marketplace: m.key, id: pid, installed, installedScope };
    });
  }
  return entry;
});

webview.postMessage({
  type: 'load',
  plugins,
  marketplaces,
  projectRoot,
});
```

---

**`_onMessage(webview, msg)` — new `install` case:**

```js
// Add to the switch/if-chain in _onMessage:
if (msg.type === 'install') {
  const { id } = msg;
  const confirmed = await vscode.window.showWarningMessage(
    `Install "${id}" locally for this project?`,
    'Install', 'Cancel'
  );
  if (confirmed !== 'Install') {
    // Re-send current state so UI reverts any optimistic indicator
    this._refresh(webview);
    return;
  }

  try {
    await runInstall(id, projectRoot);
    this._refresh(webview);       // re-read installed_plugins.json and re-render
  } catch (err) {
    vscode.window.showErrorMessage(`Install failed: ${err.message}`);
    this._refresh(webview);
  }
}
```

**New helper: `runInstall(pluginId, projectRoot)`**

```js
const { execFile } = require('child_process');
const { promisify } = require('util');
const execFileAsync = promisify(execFile);

async function runInstall(pluginId, projectRoot) {
  // Throws on non-zero exit or if 'claude' is not found
  await execFileAsync('claude', ['plugin', 'install', pluginId, '--scope', 'local'], {
    cwd: projectRoot,
    timeout: 60_000,
  });
}
```

> `require('child_process')` and `require('util')` are Node built-ins — no new dependencies.

---

## §05 · Frontend

### New surface: Install panel

The install flow lives in a collapsible **Install panel** rendered below `BulkActions` and above the plugin list footer (if any). It is a secondary surface — users who only manage existing plugins never need to open it.

**HTML version — Install panel trigger:**

```
[ + Install plugin ]          ← button in BulkActions row, right-aligned
```

Clicking opens the Install panel as an expanding section (same `is-open` pattern as project picker).

**VSCode version:** same button, same expand/collapse behaviour.

---

### Install panel layout

```
┌─────────────────────────────────────────────────────┐
│  Install plugin                            [✕ Close] │
│                                                      │
│  Marketplace  [ ceh-plugins ▾ ]                      │
│                                                      │
│  ┌──────────────────────────────────────────────┐   │
│  │  ceh-agent-coding-contract   v2.2.0  ✓ local │   │
│  │  CEH agent coding contract...                │   │
│  │  agent · coding-contract · workflow           │   │
│  │                                   [Installed] │   │
│  ├──────────────────────────────────────────────┤   │
│  │  ceh-dev-tools               v1.1.0           │   │
│  │  Scaffolding and code generation utilities.   │   │
│  │  dev · tools                                  │   │
│  │                                  [Install ↓]  │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

- **Marketplace selector** — `<select>` populated from `marketplaces[]`. One option per marketplace key. Defaults to first marketplace. Switching re-renders the plugin list below.
- **Plugin list** — one row per `MarketplacePlugin` in the selected marketplace.
  - Each row shows: `name`, `version` badge, install-status indicator, `description`, keyword tags.
  - **Install status indicator** — shown only if `installed === true`:
    - `✓ local` — installed locally for this project
    - `✓ global` — installed globally
  - **Action button**:
    - Already installed → disabled button labelled `"Installed"`, greyed out
    - Not installed → `"Install ↓"` button, active
  - If marketplace has `error`, show an inline error message instead of the plugin list.
- **No search/filter** in this iteration — plugin lists are expected to be short.

---

### Install flow (HTML version)

1. User clicks `"Install ↓"` on a plugin row.
2. Button immediately changes to `"Installing…"` and is disabled (optimistic indicator).
3. `POST /api/install` with `{ "id": "ceh-dev-tools@ceh-plugins" }`.
4. **On success:**
   - Re-fetch `GET /api/plugins` to update the main plugin list (the new plugin now appears as local).
   - Re-fetch `GET /api/marketplace` to update install-status badges in the install panel.
   - Button changes to disabled `"Installed"` with `✓ local` indicator.
5. **On failure:**
   - Button reverts to `"Install ↓"` (re-enabled).
   - Inline error message appears below the row: `"Install failed: <error from server>"`.
   - Error is dismissible (✕).

No page reload. Both fetches run in sequence after success.

---

### Install flow (VSCode version)

1. User clicks `"Install ↓"`.
2. Button becomes `"Installing…"` (disabled).
3. Webview posts `{ type: 'install', id: 'ceh-dev-tools@ceh-plugins' }` to extension.
4. Extension shows `showWarningMessage` confirmation.
5. On user confirmation: `runInstall()` runs, then `_refresh(webview)` re-sends `{ type: 'load' }` with updated data.
6. Webview re-renders everything from the new `{ type: 'load' }` payload — install panel state is restored from the new marketplace data (plugin now shows `"Installed"`).
7. On cancellation or error: `_refresh(webview)` is called; button reverts.

> **No separate `{ type: 'installResult' }` message.** The full `{ type: 'load' }` re-render is sufficient and keeps the webview stateless with respect to install results.

---

### Component tree (updated)

```
App
├── Header
├── ProjectCard
├── MockNotice                           — unchanged from ITER_03
├── PluginList
│   ├── Section: "Local plugins"
│   └── Section: "Global plugins"
├── BulkActions
│   ├── EnableAll / DisableAll           — unchanged
│   └── InstallButton                    — new: "＋ Install plugin" (right side)
└── InstallPanel                         — new, hidden until InstallButton clicked
    ├── InstallPanelHeader               — "Install plugin" title + Close button
    ├── MarketplaceSelect                — <select> of marketplace keys
    └── MarketplacePluginList
        └── MarketplacePluginRow (×N)
            ├── PluginName
            ├── VersionBadge
            ├── InstallStatusIndicator   — "✓ local" / "✓ global" or absent
            ├── Description
            ├── KeywordTags
            ├── InstallError             — inline, hidden unless install failed
            └── InstallButton            — "Install ↓" / "Installing…" / "Installed"
```

---

### State additions

```js
// Appended to state from ITER_03
let marketplaces = [
  {
    key: "ceh-plugins",
    lastUpdated: "2026-05-14T14:18:52.841Z",
    plugins: [
      {
        name: "ceh-agent-coding-contract",
        marketplace: "ceh-plugins",
        id: "ceh-agent-coding-contract@ceh-plugins",
        description: "CEH agent coding contract...",
        version: "2.2.0",
        author: "cheneeheng",
        keywords: ["agent", "coding-contract", "workflow"],
        installed: true,
        installedScope: "local"
      }
    ]
  }
]

let installPanelOpen = false;
let selectedMarketplace = marketplaces[0]?.key ?? null;
```

---

### CSS additions to `styles.css`

> Add to **both** `html/styles.css` and `vscode-extension/webview/styles.css`.

```css
/* ── Install panel ──────────────────────────────── */

.install-panel {
  display: none;
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 12px 14px;
  margin-top: 12px;
  background: var(--surface);
}

.install-panel.is-open {
  display: block;
}

.install-panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 12px;
}

.install-panel-title {
  font-size: 0.85rem;
  font-weight: 700;
  color: var(--fg);
}

.install-panel-close {
  background: none;
  border: none;
  color: var(--fg-muted);
  cursor: pointer;
  font-size: 0.85rem;
  padding: 0 4px;
}

.marketplace-select-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 12px;
}

.marketplace-select-label {
  font-size: 0.75rem;
  color: var(--fg-muted);
  white-space: nowrap;
}

.marketplace-select {
  font-size: 0.8rem;
  padding: 3px 6px;
  border: 1px solid var(--border);
  border-radius: 4px;
  background: var(--bg);
  color: var(--fg);
}

/* ── Marketplace plugin rows ───────────────────── */

.mp-plugin-list {
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.mp-plugin-row {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 4px 10px;
  align-items: start;
  padding: 8px 10px;
  border-radius: 4px;
  background: var(--bg);
  border: 1px solid var(--border);
}

.mp-plugin-row + .mp-plugin-row {
  margin-top: 4px;
}

.mp-plugin-main {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
}

.mp-plugin-name {
  font-size: 0.85rem;
  font-weight: 600;
  color: var(--fg);
}

.install-status {
  font-size: 0.68rem;
  color: #3a8a3a;
  font-weight: 600;
}

:root[data-theme="dark"] .install-status,
:root[data-context="vscode"] .install-status {
  color: #6bcb6b;
}

@media (prefers-color-scheme: dark) {
  :root:not([data-theme]) .install-status {
    color: #6bcb6b;
  }
}

.mp-plugin-description {
  font-size: 0.75rem;
  color: var(--fg-muted);
  margin-top: 2px;
  grid-column: 1;
}

.mp-keyword-list {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  margin-top: 4px;
  grid-column: 1;
}

.mp-keyword {
  font-size: 0.65rem;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 3px;
  padding: 1px 5px;
  color: var(--fg-muted);
}

.mp-install-col {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 4px;
  grid-column: 2;
  grid-row: 1 / 4;
}

.mp-install-btn {
  font-size: 0.75rem;
  padding: 3px 10px;
  border-radius: 4px;
  cursor: pointer;
  white-space: nowrap;
  border: 1px solid var(--accent);
  background: transparent;
  color: var(--accent);
}

.mp-install-btn:hover:not(:disabled) {
  background: var(--accent);
  color: #ffffff;
}

.mp-install-btn:disabled {
  border-color: var(--border);
  color: var(--fg-muted);
  cursor: default;
}

.mp-install-error {
  display: none;
  font-size: 0.72rem;
  color: #cc4444;
  margin-top: 4px;
  grid-column: 1 / 3;
}

.mp-install-error.visible {
  display: block;
}

/* ── BulkActions row update ────────────────────── */

.bulk-actions {
  display: flex;
  justify-content: space-between;   /* existing items left, install button right */
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
}

.bulk-install-btn {
  font-size: 0.78rem;
  padding: 4px 12px;
  border-radius: 4px;
  border: 1px solid var(--accent);
  background: transparent;
  color: var(--accent);
  cursor: pointer;
}

.bulk-install-btn:hover {
  background: var(--accent);
  color: #ffffff;
}
```

---

### JS additions (vanilla — shared by `index.html` and `panel.html`)

```js
// ── Install panel state ────────────────────────────
let installPanelOpen = false;
let selectedMarketplace = null;   // key string

function openInstallPanel() {
  installPanelOpen = true;
  if (!selectedMarketplace && marketplaces.length > 0) {
    selectedMarketplace = marketplaces[0].key;
  }
  renderInstallPanel();
  document.getElementById('install-panel').classList.add('is-open');
}

function closeInstallPanel() {
  installPanelOpen = false;
  document.getElementById('install-panel').classList.remove('is-open');
}

// ── Render install panel ───────────────────────────
function renderInstallPanel() {
  const panel = document.getElementById('install-panel');

  const options = marketplaces
    .map(m => `<option value="${escapeHtml(m.key)}" ${m.key === selectedMarketplace ? 'selected' : ''}>${escapeHtml(m.key)}</option>`)
    .join('');

  const mp = marketplaces.find(m => m.key === selectedMarketplace);
  const pluginListHtml = mp
    ? (mp.error
        ? `<div class="mp-install-error visible">${escapeHtml(mp.error)}</div>`
        : mp.plugins.map(renderMpPluginRow).join(''))
    : '';

  panel.innerHTML = `
    <div class="install-panel-header">
      <span class="install-panel-title">Install plugin</span>
      <button class="install-panel-close" onclick="closeInstallPanel()">✕ Close</button>
    </div>
    <div class="marketplace-select-row">
      <span class="marketplace-select-label">Marketplace</span>
      <select class="marketplace-select" onchange="selectedMarketplace = this.value; renderInstallPanel()">
        ${options}
      </select>
    </div>
    <div class="mp-plugin-list">${pluginListHtml}</div>
  `;
}

function renderMpPluginRow(p) {
  const installed = p.installed;
  const scopeLabel = installed
    ? `<span class="install-status">✓ ${escapeHtml(p.installedScope)}</span>`
    : '';

  const keywords = (p.keywords || [])
    .map(k => `<span class="mp-keyword">${escapeHtml(k)}</span>`)
    .join('');

  const btnLabel  = installed ? 'Installed' : 'Install ↓';
  const btnDisabled = installed ? 'disabled' : '';
  const btnOnclick  = installed ? '' : `onclick="installPlugin('${escapeHtml(p.id)}')"`;

  return `
    <div class="mp-plugin-row" id="mp-row-${CSS.escape(p.id)}">
      <div class="mp-plugin-main">
        <span class="mp-plugin-name">${escapeHtml(p.name)}</span>
        ${p.version ? `<span class="version-badge">v${escapeHtml(p.version)}</span>` : ''}
        ${scopeLabel}
      </div>
      <div class="mp-install-col">
        <button class="mp-install-btn" id="mp-btn-${CSS.escape(p.id)}" ${btnDisabled} ${btnOnclick}>
          ${btnLabel}
        </button>
      </div>
      ${p.description ? `<div class="mp-plugin-description">${escapeHtml(p.description)}</div>` : ''}
      ${keywords ? `<div class="mp-keyword-list">${keywords}</div>` : ''}
      <div class="mp-install-error" id="mp-err-${CSS.escape(p.id)}"></div>
    </div>
  `;
}

// ── Install action ─────────────────────────────────
async function installPlugin(id) {
  const btn = document.getElementById(`mp-btn-${CSS.escape(id)}`);
  const errEl = document.getElementById(`mp-err-${CSS.escape(id)}`);

  btn.textContent = 'Installing…';
  btn.disabled = true;
  errEl.textContent = '';
  errEl.classList.remove('visible');

  try {
    // HTML version: POST to server
    // VSCode version: post message, wait for refresh (see note below)
    if (typeof acquireVsCodeApi !== 'undefined') {
      vscodeApi.postMessage({ type: 'install', id });
      // UI update comes via the next { type: 'load' } message — no further action here.
      return;
    }

    const res  = await fetch('/api/install', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id }),
    });
    const data = await res.json();

    if (!data.ok) throw new Error(data.error || 'Unknown error');

    // Refresh both plugin list and marketplace data
    await Promise.all([fetchPlugins(), fetchMarketplace()]);
    // renderInstallPanel() is called inside fetchMarketplace() after state update
  } catch (err) {
    btn.textContent = 'Install ↓';
    btn.disabled = false;
    errEl.textContent = `Install failed: ${err.message}`;
    errEl.classList.add('visible');
  }
}

// ── Fetch marketplace data (HTML version) ──────────
async function fetchMarketplace() {
  const res  = await fetch('/api/marketplace');
  const data = await res.json();
  marketplaces = data.marketplaces || [];
  if (installPanelOpen) renderInstallPanel();
}
```

> **VSCode note:** `vscodeApi` is the object returned by `acquireVsCodeApi()`, called once at the top of `panel.html`'s inline script and stored in a module-level variable. After posting `{ type: 'install' }`, the button stays in `"Installing…"` state until the extension responds with a `{ type: 'load' }` message, which triggers a full re-render including the install panel (via `renderInstallPanel()` called from the load handler if `installPanelOpen` is true).

> **`CSS.escape()`** is available in all modern browsers and recent VSCode webview. Use it to safely construct element IDs from plugin id strings that contain `@`.

---

### Loading state for install panel

The install panel is populated from the same `{ type: 'load' }` payload (VSCode) or from `GET /api/marketplace` (HTML). No separate loading spinner is added for the panel in this iteration — it opens already populated because the data is fetched eagerly on page load. If `fetchMarketplace()` has not yet completed when the user clicks "Install plugin", the panel opens with an empty marketplace list; the select will populate once the fetch resolves.

---

### Empty states (additions)

- `marketplaces` is empty (no `known_marketplaces.json`): install panel shows `"No marketplaces configured. Add marketplaces via Claude Code before installing plugins."`
- Selected marketplace has `error`: show the error string in place of the plugin list.
- Selected marketplace has `plugins: []` and no error: show `"No plugins found in this marketplace."`.

---

## Deferred

- **Search / filter within install panel** — deferred; plugin lists are short enough to scan visually for now.
- **Global scope install** — `--scope local` is the only option exposed. A scope selector (`local` / `global`) could be added to the install panel in a future iteration.
- **Uninstall** — not in scope. Users manage uninstalls via `claude plugin uninstall` in the terminal.
- **Marketplace refresh** (re-run `claude plugin marketplace update`) — the UI shows whatever is in `known_marketplaces.json` at load time; triggering a fetch from the remote git source is out of scope.
- **Install progress streaming** — `claude plugin install` output is captured only after process exit; streaming stdout/stderr line-by-line into the UI is deferred.
- **`styles.css` sync** — still manual between `html/` and `vscode-extension/webview/`. Now more urgent; a `Makefile` target or symlink should be addressed before the next iteration adds more CSS.
- **Windows path normalisation edge cases** — carried from ITER_03 deferred list.
- **File watching** — carried from ITER_01/ITER_02/ITER_03 deferred list.
- **Animated expand/collapse** — carried from ITER_02 deferred list.
- **`.vsix` packaging** — carried from prior deferred list.
