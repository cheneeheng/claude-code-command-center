# claude-code-plugin-toggler

A developer tool for managing Claude Code skill plugins. Toggle plugins on/off per-project from a browser UI or directly inside VSCode. Browse and install new plugins from known marketplaces without leaving the UI.

**User guides:** [HTML version](docs/user-guide-html.md) · [VSCode extension](docs/user-guide-vscode.md)

## How it works

Reads installed plugins from `~/.claude/plugins/installed_plugins.json` (global, managed externally) and writes enabled/disabled state to `.claude/settings.local.json` in the current project root. Claude Code picks up the updated settings on the next session.

```
~/.claude/plugins/installed_plugins.json   (global — source of installed plugins)
~/.claude/plugins/known_marketplaces.json  (global — marketplace registry)
        │
        ├──▶ html/server.py  ←HTTP/SSE→  html/index.html
        └──▶ vscode-extension/extension.js  ←Webview→  vscode-extension/webview/panel.html
                    │
                    ▼
        <project>/.claude/settings.local.json   (per-project — enabled state)
```

Both surfaces use the same read/merge/write logic (implemented independently in Python and Node.js). `server.py` is stdlib-only. The VSCode extension has no npm runtime dependencies.

## Quick start

**HTML version** — run from the root of the project you want to manage:

```bash
cd /your/project
python3 /path/to/claude-code-plugin-toggler/html/server.py        # port 7779
python3 /path/to/claude-code-plugin-toggler/html/server.py 8080   # custom port
```

Convenience scripts in `html/`: `start.sh` (Linux/macOS), `start.ps1` / `start.bat` (Windows).

**VSCode extension** — dev mode: open `vscode-extension/` and press `F5`. To package:

```bash
cd vscode-extension && vsce package   # produces .vsix; prepackage hook syncs CSS
```

## Data format

**`~/.claude/plugins/installed_plugins.json`**
```json
{ "plugins": { "frontend-design@anthropic": {}, "docx@anthropic": {} } }
```

**`~/.claude/plugins/known_marketplaces.json`**
```json
{
  "ceh-plugins": {
    "installLocation": "C:\\Users\\user\\.claude\\plugins\\marketplaces\\ceh-plugins",
    "lastUpdated": "2026-05-14T14:18:52.841Z"
  }
}
```

**`.claude/settings.local.json`** (written by this tool)
```json
{ "enabledPlugins": { "frontend-design@anthropic": true, "docx@anthropic": false } }
```

Plugin ID format: `name@marketplace`.

Skills and agents are read from the plugin's install path at load time:

```
<installPath>/skills/<skill-dir>/SKILL.md     # YAML front matter: name, description
<installPath>/agents/<agent>.md               # YAML front matter: name, description
```

Marketplace plugin listings are read from:

```
<installLocation>/.claude-plugin/marketplace.json
```

If `installed_plugins.json` is missing, `server.py` falls back to `MOCK_PLUGINS` and sets `"mock": true` in the API response.

## CSS sync

`html/styles.css` is canonical. `vscode-extension/webview/styles.css` is generated — do not edit it directly.

```bash
make sync-css           # macOS / Linux
.\scripts\sync-css.ps1  # Windows
```

`vsce package` runs this automatically via the `prepackage` npm script.

## Requirements

- **HTML version:** Python 3.13+ (stdlib only)
- **VSCode extension:** VSCode 1.80+
- **Install feature:** `claude` CLI on `PATH`
- **CSS sync:** `make` (macOS/Linux) or PowerShell (Windows)

## Troubleshooting

**`[WinError 10053]` in server output (Windows only):** benign — the browser closed a connection before the server finished reading it. Suppressed at the `handle_error` level; no action needed. See [HTML user guide](docs/user-guide-html.md#winError-10053-in-the-terminal-windows) for details.

See [CHANGELOG.md](CHANGELOG.md) for release history.
