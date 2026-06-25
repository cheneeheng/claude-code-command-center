---
artifact: SKELETON
status: ready
created: 2026-05-13
app: claude-code-plugin-toggler — Claude Code plugin manager UI
stack: Python stdlib, vanilla JS/HTML, Node.js, VSCode Extension API
sections: [01, 02, 03, 04, 05]
---

## §01 · Concept

A developer tool for managing Claude Code skill plugins across two surfaces: a standalone browser UI (HTML + Python server) and a VSCode extension. Both surfaces read installed plugins from `~/.claude/plugins/installed_plugins.json` and write enabled/disabled state to `.claude/settings.local.json` in the current project root. The single most important flow: open the UI, see all installed plugins, flip a toggle, close — the project's `settings.local.json` is updated and Claude Code picks it up on next session.

---

## §02 · Architecture

### Component diagram

```
~/.claude/plugins/installed_plugins.json   (read only — source of plugins)
        │
        ▼
  [ Plugin loader ]
        │
        ├──▶ [ HTML version ]  server.py (HTTP) ◀──▶ index.html (browser)
        │
        └──▶ [ VSCode version ] extension.js ◀──▶ panel.html (Webview)
                    │
                    ▼
        ./.claude/settings.local.json      (read + write — enabled state)
```

### Data model

**InstalledPlugin**
- `id` — string, format `pluginname@marketplace` (e.g. `frontend-design@anthropic`)
- `name` — string, part before `@`
- `marketplace` — string, part after `@`
- `enabled` — boolean, derived from `settings.local.json`

**SettingsLocal** (`.claude/settings.local.json`)
```json
{
  "enabledPlugins": {
    "frontend-design@anthropic": true,
    "docx@anthropic": false
  }
}
```

**InstalledPlugins** (`~/.claude/plugins/installed_plugins.json`)
```json
{
  "plugins": [
    "frontend-design@anthropic",
    "docx@anthropic"
  ]
}
```

### API surface (HTML version only)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/plugins` | Returns merged plugin list with enabled state |
| `POST` | `/api/toggle` | Sets one plugin's enabled state in `settings.local.json` |
| `GET` | `/` | Serves `index.html` |

`GET /api/plugins` response shape:
```json
{
  "plugins": [
    { "id": "frontend-design@anthropic", "name": "frontend-design", "marketplace": "anthropic", "enabled": true }
  ],
  "project_root": "/path/to/project"
}
```

`POST /api/toggle` request body:
```json
{ "id": "frontend-design@anthropic", "enabled": false }
```

`POST /api/toggle` response:
```json
{ "ok": true }
```

No auth. CORS: localhost only. Pagination: not needed (plugin list is small).

---

## §03 · Tech Stack

**HTML version**
- Python 3.13+ (stdlib only — `http.server`, `json`, `pathlib`, `os`)
- Vanilla JS + HTML — no framework, no bundler
- Run: `python3 server.py [port]` from project root (default port 7779)

**VSCode extension**
- Node.js (whatever ships with VSCode — no separate runtime needed)
- VSCode Extension API (`vscode` module)
- No npm dependencies beyond `@types/vscode` for dev
- Webview panel renders `panel.html` (vanilla JS — same UI logic as `index.html`)
- Run (dev): `F5` in VSCode with extension open
- Package: `vsce package` → `.vsix` for local install

---

## §04 · Backend

### HTML version — `server.py`

```
html/
├── server.py
└── index.html
```

**Module structure (all in server.py):**
- `load_installed_plugins()` — reads `~/.claude/plugins/installed_plugins.json`, returns list of id strings
- `load_settings_local(project_root)` — reads `.claude/settings.local.json`, returns dict (empty dict if file missing)
- `save_settings_local(project_root, settings)` — writes `.claude/settings.local.json`, creates `.claude/` dir if needed
- `merge(plugins, settings)` — zips plugin list with enabled state, returns list of `InstalledPlugin` dicts
- `RequestHandler` — subclass of `BaseHTTPRequestHandler`, routes `GET /`, `GET /api/plugins`, `POST /api/toggle`

**Environment variables:** none required.

**How to run:**
```bash
cd /your/project
python3 ~/claude-code-plugin-toggler/html/server.py
# or with custom port:
python3 ~/claude-code-plugin-toggler/html/server.py 8080
```

`project_root` = `os.getcwd()` at server start.

---

### VSCode extension — `extension.js`

```
vscode-extension/
├── package.json
├── extension.js
└── webview/
    └── panel.html
```

**Extension entry points:**
- `activate(context)` — registers command `claude-code-plugin-toggler.manage`
- Command handler — opens `SkillsPanel` webview
- `SkillsPanel` class:
  - `constructor` — creates webview panel, loads `panel.html`, calls `_refresh()`
  - `_refresh()` — reads plugins + settings, posts `{ type: 'load', plugins: [...] }` message to webview
  - `_onMessage(msg)` — handles `{ type: 'toggle', id, enabled }` from webview:
    1. Shows `vscode.window.showWarningMessage` confirmation: `"Set <id> to <enabled>?"` with Yes/No buttons
    2. On Yes: writes `settings.local.json`, calls `_refresh()`
    3. On No: calls `_refresh()` (resets UI state)

**File helpers (same logic as Python version, in Node.js):**
- `loadInstalledPlugins()` — reads `~/.claude/plugins/installed_plugins.json`
- `loadSettingsLocal(projectRoot)` — reads `.claude/settings.local.json`
- `saveSettingsLocal(projectRoot, settings)` — writes `.claude/settings.local.json`

`projectRoot` = `vscode.workspace.workspaceFolders[0].uri.fsPath`.

**package.json essentials:**
```json
{
  "name": "claude-code-plugin-toggler",
  "displayName": "Claude Code Plugin Toggler",
  "version": "0.0.1",
  "engines": { "vscode": "^1.80.0" },
  "activationEvents": [],
  "main": "./extension.js",
  "contributes": {
    "commands": [{
      "command": "claude-code-plugin-toggler.manage",
      "title": "Skills: Manage Plugins"
    }]
  }
}
```

---

## §05 · Frontend

### Screens

| Screen | Route/Surface | Description |
|--------|--------------|-------------|
| Plugin list | `/` (HTML) or Webview panel (VSCode) | Single screen — all plugins as toggle rows |

### Component tree

```
App
├── Header         — title + project path currently being written to
├── PluginList
│   └── PluginRow (×N)
│       ├── PluginName   — "frontend-design"
│       ├── MarketplaceBadge — "@anthropic"
│       └── Toggle       — checkbox/switch, fires toggle on change
└── BulkActions    — "Enable all" / "Disable all" buttons
```

### State

```js
// Loaded from /api/plugins (HTML) or webview message (VSCode)
let plugins = [
  { id: "frontend-design@anthropic", name: "frontend-design", marketplace: "anthropic", enabled: true }
]
```

Toggle fires immediately (optimistic UI), then calls `/api/toggle` (HTML) or posts `{ type: 'toggle' }` message (VSCode). On error, reverts.

### Loading + error states

- Loading: show "Loading plugins..." text while fetch is in flight
- Error (file not found / parse error): show inline error message with the path that failed
- Empty state: "No plugins installed. Install plugins to `~/.claude/plugins/`."

### Placeholder data strategy

During skeleton build: `server.py` returns hardcoded plugin list if `installed_plugins.json` is missing, clearly marked as mock data in the response (`"mock": true`).

---

## Deferred

- Plugin metadata beyond `id` (description, version, icon) — not in `installed_plugins.json` currently
- Install/uninstall plugins from the UI — out of scope, managed externally
- Project path picker in the HTML version (currently always `cwd`) — deferred
- `.vsix` packaging + publish workflow — deferred to next iteration
