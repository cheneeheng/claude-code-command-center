---
artifact: ITER_01
status: ready
created: 2026-05-14
scope: Shared styling + theming, plugin tier UI, VSCode sidebar, launcher scripts, HTML working-directory picker
sections_changed: [02, 03, 04, 05]
sections_unchanged: [01]
---

## §01 · Concept
> Unchanged — see SKELETON.md §01

---

## §02 · Architecture

### Component diagram (updated)

```
~/.claude/plugins/installed_plugins.json   (read only — source of plugins)
        │
        ▼
  [ Plugin loader ]
        │
        ├──▶ [ HTML version ]
        │       server.py (HTTP) ◀──▶ index.html (browser)
        │       start.sh / start.bat / start.ps1  (launchers)
        │
        └──▶ [ VSCode version ]
                extension.js ◀──▶ panel.html (Webview sidebar)
                        │
                        ▼
        ./.claude/settings.local.json      (read + write — enabled state)

Shared asset:
        html/styles.css   ←── loaded by both index.html and panel.html
```

### Data model (updated)

**InstalledPlugin** — same shape as SKELETON, one new derived field:

- `id` — string, `pluginname@marketplace`
- `name` — string
- `marketplace` — string
- `enabled` — boolean, from `settings.local.json`
- `scope` — `"local"` | `"inherited"` — **new**
  - `"local"` → plugin has an explicit entry in `settings.local.json`
  - `"inherited"` → plugin is in `installed_plugins.json` but absent from `settings.local.json`

**SettingsLocal** — unchanged, see SKELETON.md §02

**InstalledPlugins** — unchanged, see SKELETON.md §02

### API surface (HTML version — changes only)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/plugins` | Returns merged plugin list — now includes `scope` field per plugin |
| `POST` | `/api/toggle` | Unchanged |
| `POST` | `/api/set-project` | **New** — updates `project_root` in memory for this server session |
| `GET` | `/` | Unchanged |

`POST /api/set-project` request body:
```json
{ "path": "/absolute/path/to/project" }
```

`POST /api/set-project` response:
```json
{ "ok": true, "project_root": "/absolute/path/to/project" }
```

Error if path does not exist:
```json
{ "ok": false, "error": "Path does not exist: /bad/path" }
```

`GET /api/plugins` response — `scope` field added:
```json
{
  "plugins": [
    { "id": "frontend-design@anthropic", "name": "frontend-design", "marketplace": "anthropic", "enabled": true, "scope": "local" },
    { "id": "docx@anthropic", "name": "docx", "marketplace": "anthropic", "enabled": false, "scope": "inherited" }
  ],
  "project_root": "/path/to/project"
}
```

`POST /api/toggle` — unchanged. When called for an `inherited` plugin it writes the explicit entry into `settings.local.json`, promoting it to `"local"` scope.

---

## §03 · Tech Stack

New in this iteration:

- **`styles.css`** — shared vanilla CSS, no preprocessor. CSS custom properties for theming. No new runtime dependency.
- **Launcher scripts** — pure shell (`bash`, `cmd`, `powershell`). No new runtime dependency.
- **VSCode sidebar** — uses `WebviewViewProvider` API (already available in `vscode ^1.80.0`). No new npm dependency. Requires a 16×16 or 24×24 SVG icon asset.

No version changes to existing stack entries.

---

## §04 · Backend

### File structure (updated)

```
html/
├── server.py
├── index.html
├── styles.css          ← new (shared stylesheet)
├── start.sh            ← new
├── start.bat           ← new
└── start.ps1           ← new

vscode-extension/
├── package.json
├── extension.js
├── icon.svg            ← new (sidebar Activity Bar icon)
└── webview/
    ├── panel.html
    └── styles.css      ← new (copy of html/styles.css — kept in sync manually for now)
    # styles.css must live inside webview/ so localResourceRoots can serve it via asWebviewUri
```

### `server.py` changes

**`merge(plugins, settings)`** — add `scope` derivation:
```python
def merge(plugins, settings):
    enabled_map = settings.get("enabledPlugins", {})
    result = []
    for pid in plugins:
        name, marketplace = pid.split("@", 1)
        in_local = pid in enabled_map
        result.append({
            "id": pid,
            "name": name,
            "marketplace": marketplace,
            "enabled": enabled_map.get(pid, True),   # default inherited = enabled
            "scope": "local" if in_local else "inherited"
        })
    return result
```

> **Default for inherited plugins:** treat as `enabled: true` unless a future global settings file says otherwise. Document this assumption inline with a comment.

**New handler: `POST /api/set-project`**
```python
# pseudocode
path = body["path"]
if not os.path.isdir(path):
    respond 400 { "ok": False, "error": f"Path does not exist: {path}" }
self.server.project_root = path
respond 200 { "ok": True, "project_root": path }
```

Pass `project_root` through the server instance (set on `HTTPServer` subclass) so the handler can mutate it across requests.

**`RequestHandler.do_GET` for static files** — serve `styles.css` alongside `index.html`:
```python
elif path == "/styles.css":
    self._serve_file("styles.css", "text/css")
```

### Launcher scripts

**`start.sh`**
```bash
#!/usr/bin/env bash
PORT=${1:-7779}
PROJECT_ROOT="$(pwd)"          # capture caller's cwd before cd-ing into html/
cd "$(dirname "$0")"           # cd into html/ so server.py can find its assets
python3 server.py "$PORT" "$PROJECT_ROOT" &
SERVER_PID=$!
# wait up to 3s for server to be ready
READY=0
for i in 1 2 3; do
  sleep 1
  if curl -sf "http://localhost:$PORT/" > /dev/null; then
    READY=1
    break
  fi
done
if [ $READY -eq 0 ]; then
  echo "Warning: server may not be ready yet"
fi
xdg-open "http://localhost:$PORT/" 2>/dev/null || open "http://localhost:$PORT/"
echo "Skills Toggle running on http://localhost:$PORT (PID $SERVER_PID)"
```

> **Note:** `server.py` must accept an optional second positional argument `project_root`. When provided, it overrides `os.getcwd()` as the initial `project_root`. Add to `server.py` startup:
> ```python
> project_root = sys.argv[2] if len(sys.argv) > 2 else os.getcwd()
> ```

**`start.bat`**
```bat
@echo off
set PORT=7779
set PROJECT_ROOT=%CD%
cd /d "%~dp0"
start /B python server.py %PORT% "%PROJECT_ROOT%"
timeout /t 2 /nobreak >nul
start http://localhost:%PORT%/
```

**`start.ps1`**
```powershell
$port = 7779
$projectRoot = (Get-Location).Path
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Start-Process python -ArgumentList "server.py $port `"$projectRoot`"" -WorkingDirectory $scriptDir -WindowStyle Hidden
Start-Sleep -Seconds 2
Start-Process "http://localhost:$port/"
```

### `extension.js` changes

Replace `WebviewPanel` with `WebviewViewProvider`:

```js
class SkillsViewProvider {
  static viewType = 'skillsToggle.pluginList';

  constructor(extensionUri) {
    this._extensionUri = extensionUri;
  }

  resolveWebviewView(webviewView) {
    const stylesUri = webviewView.webview.asWebviewUri(
      vscode.Uri.joinPath(this._extensionUri, 'webview', 'styles.css')
    );
    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [vscode.Uri.joinPath(this._extensionUri, 'webview')]
    };
    webviewView.webview.html = this._getHtml(webviewView.webview, stylesUri);
    this._refresh(webviewView.webview);
    webviewView.webview.onDidReceiveMessage(msg => this._onMessage(webviewView.webview, msg));
  }

  // _refresh(webview) — takes webview as argument (differs from SKELETON's SkillsPanel
  //   which held a panel reference internally). Reads plugins + settings, posts
  //   { type: 'load', plugins: [...] } to webview.
  // _onMessage(webview, msg) — same change: webview passed explicitly.
  // _getHtml(webview, stylesUri) — injects stylesUri into the <link> tag.
}

function activate(context) {
  const provider = new SkillsViewProvider(context.extensionUri);
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider(SkillsViewProvider.viewType, provider)
  );
}
```

**`package.json` changes** — replace `commands` contribution with `views` + `viewsContainers`:

```json
{
  "contributes": {
    "viewsContainers": {
      "activitybar": [{
        "id": "skillsToggle",
        "title": "Skills Toggle",
        "icon": "icon.svg"
      }]
    },
    "views": {
      "skillsToggle": [{
        "type": "webview",
        "id": "skillsToggle.pluginList",
        "name": "Plugins"
      }]
    }
  }
}
```

Remove the `commands` contribution entirely — no command palette entry needed.

---

## §05 · Frontend

### Shared stylesheet — `styles.css`

**Theme architecture:**

```css
/* --- Standalone theme tokens (HTML version) --- */
:root[data-theme="light"] {
  --bg: #ffffff;
  --surface: #f5f5f5;
  --fg: #111111;
  --fg-muted: #666666;
  --border: #e0e0e0;
  --accent: #0066cc;
  --inherited-bg: #f0f0f0;
  --inherited-fg: #999999;
}

:root[data-theme="dark"] {
  --bg: #1e1e1e;
  --surface: #2a2a2a;
  --fg: #eeeeee;
  --fg-muted: #aaaaaa;
  --border: #3a3a3a;
  --accent: #4da3ff;
  --inherited-bg: #2a2a2a;
  --inherited-fg: #666666;
}

/* Follow System — default when no data-theme is set */
/* Light fallback must be declared first as the base :root */
:root {
  --bg: #ffffff;
  --surface: #f5f5f5;
  --fg: #111111;
  --fg-muted: #666666;
  --border: #e0e0e0;
  --accent: #0066cc;
  --inherited-bg: #f0f0f0;
  --inherited-fg: #999999;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme]) {
    --bg: #1e1e1e;
    --surface: #2a2a2a;
    --fg: #eeeeee;
    --fg-muted: #aaaaaa;
    --border: #3a3a3a;
    --accent: #4da3ff;
    --inherited-bg: #2a2a2a;
    --inherited-fg: #666666;
  }
}

/* --- VSCode theme bridge --- */
:root[data-context="vscode"] {
  --bg: var(--vscode-editor-background);
  --surface: var(--vscode-sideBar-background, var(--vscode-editor-background));
  --fg: var(--vscode-editor-foreground);
  --fg-muted: var(--vscode-descriptionForeground);
  --border: var(--vscode-panel-border, #444);
  --accent: var(--vscode-textLink-foreground);
  --inherited-bg: var(--vscode-input-background);
  --inherited-fg: var(--vscode-disabledForeground, #666);
}
```

VSCode context is set by a one-liner at the top of `panel.html`'s inline script:
```js
if (typeof acquireVsCodeApi !== 'undefined') {
  document.documentElement.setAttribute('data-context', 'vscode');
}
```

### Component tree (updated)

```
App
├── Header
│   ├── Title ("Skills Toggle")
│   ├── ProjectPath            — current project_root, shown as muted text
│   ├── ProjectPicker          — HTML version only: text input + "Change" button
│   └── ThemeToggle            — HTML version only: Light / Dark / System buttons
├── PluginList
│   ├── Section: "Local"       — plugins with scope="local" (rendered first)
│   │   └── PluginRow (×N)
│   │       ├── PluginName
│   │       ├── MarketplaceBadge
│   │       └── Toggle         — fully interactive
│   └── Section: "Inherited"   — plugins with scope="inherited"
│       └── PluginRow (×N)
│           ├── PluginName     — dimmed via --inherited-fg
│           ├── MarketplaceBadge
│           ├── InheritedBadge — small label "global default" + tooltip
│           └── OverrideButton — "Override locally" — on click: POST /api/toggle (or VSCode message), promotes to local
└── BulkActions                — "Enable all" / "Disable all" (acts on local-scope plugins only)
```

### State (updated from SKELETON.md §05)

```js
// Loaded from /api/plugins (HTML) or webview message (VSCode)
// scope field is new in this iteration
let plugins = [
  { id: "frontend-design@anthropic", name: "frontend-design", marketplace: "anthropic", enabled: true, scope: "local" },
  { id: "docx@anthropic", name: "docx", marketplace: "anthropic", enabled: true, scope: "inherited" }
]
```

**Locally managed row:** normal toggle. `POST /api/toggle` (HTML) or `{ type: 'toggle' }` message (VSCode).

**Inherited row:**
- Toggle is read-only/disabled (shows current inherited state visually but cannot be flipped directly)
- "Override locally" button is the only action
- Clicking "Override locally" calls `POST /api/toggle` (HTML) or posts `{ type: 'toggle' }` (VSCode) with `enabled: <current inherited value>` — it **pins the current state**, it does not flip it. The user can then flip it via the now-live toggle.
- After the write, the row re-renders as a local row with a live toggle
- Tooltip on the `InheritedBadge`: *"This plugin has no local setting. It is using the global default (enabled). Click 'Override locally' to manage it in this project."*
- VSCode: "Override locally" uses the same `_onMessage` path as a regular toggle. Show the same `showWarningMessage` confirmation: `"Pin <id> to local settings?"` with Yes/No.

### Theme toggle (HTML version only)

Three buttons: `Light` | `Dark` | `System`. Active state highlighted with `--accent` border.

```js
function setTheme(t) {          // t = 'light' | 'dark' | null (system)
  if (t) document.documentElement.setAttribute('data-theme', t);
  else   document.documentElement.removeAttribute('data-theme');
  localStorage.setItem('skills-theme', t ?? '');
}
// On load:
const saved = localStorage.getItem('skills-theme');
if (saved) setTheme(saved);
```

VSCode surface: theme toggle is not rendered. `data-context="vscode"` is set instead and VSCode variables handle it.

### Project picker (HTML version only)

Rendered in the `Header`, below the current path:

```html
<div class="project-picker">
  <input type="text" id="project-path" placeholder="/path/to/project" />
  <button id="change-project">Change</button>
  <span id="project-error" class="error hidden"></span>
</div>
```

On "Change" click:
1. Disable input + button
2. `POST /api/set-project` with `{ path: inputValue }`
3. On `ok: true` → update displayed path, re-fetch `/api/plugins`, clear error
4. On `ok: false` → show `error` span with message from response, re-enable input

### Loading + error states
> Unchanged — see SKELETON.md §05

### Placeholder / mock data
> Unchanged — see SKELETON.md §05. Mock response now includes `"scope": "inherited"` on all mock entries to exercise the inherited UI path.

---

## Deferred

- Global default value for inherited plugins (currently hardcoded as `enabled: true`) — deferred until a global settings file is defined
- Bulk actions behaviour for inherited-scope plugins (currently acts on local only) — defer until UX is validated
- Theme preference persistence in VSCode (follows VSCode, user has no control) — by design, not deferred
- `.vsix` packaging + publish workflow — see SKELETON.md Deferred
- Plugin metadata (description, version, icon) — see SKELETON.md Deferred
- **File watching** — auto-refresh the UI when `settings.local.json` changes on disk without a manual reload; suggested next iteration
- **`styles.css` sync between `html/` and `vscode-extension/webview/`** — currently kept in sync manually; a build step (e.g. a `Makefile` copy or symlink) should be added before the project grows further