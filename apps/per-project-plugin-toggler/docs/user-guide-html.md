# User Guide — HTML version

The HTML version is a lightweight browser UI backed by a local Python server. It requires no installation beyond Python 3.13 and runs entirely from the terminal.

## Prerequisites

- Python 3.13 or later (no extra packages needed)
- A modern browser (Chrome, Firefox, Edge)
- The `claude` CLI on `PATH` if you want to install plugins from the marketplace

## Starting the server

Run the server from the root of the project you want to manage. The working directory at startup becomes the fixed project root — the tool reads and writes `.claude/settings.local.json` relative to it.

```bash
cd /your/project
python3 /path/to/claude-code-plugin-toggler/html/server.py        # default port 7779
python3 /path/to/claude-code-plugin-toggler/html/server.py 8080   # custom port
```

**Windows convenience scripts** (run from within the `html/` directory):

```powershell
.\start.ps1           # PowerShell
start.bat             # Command Prompt
```

Open `http://127.0.0.1:7779` (or your custom port) in a browser.

## Stopping the server

Click **Stop server** in the top-right corner of the UI, or press `Ctrl+C` in the terminal.

## Understanding the plugin list

Plugins are shown in two sections:

| Section | What it means |
|---------|---------------|
| **Local** | Has an explicit entry in this project's `.claude/settings.local.json`. You can toggle it on or off directly. |
| **Inherited** | No local override — the plugin is treated as enabled by Claude Code. To toggle it, click **Localize** first to pin it into local settings. |

### Enabling / disabling a plugin

Flip the toggle on any **Local** plugin. The change is written to `.claude/settings.local.json` immediately. Claude Code picks it up on the next session start.

### Localizing an inherited plugin

1. Find the plugin in the **Inherited** section.
2. Click **Localize**. The plugin moves to the **Local** section with its current state pinned.
3. Now toggle it as needed.

### Bulk actions

The **Enable all** and **Disable all** buttons in the header apply only to plugins already in the **Local** section. Inherited plugins are not affected.

## Viewing plugin skills

Each plugin row shows a skill count badge. Click the badge (or the row disclosure) to expand an inline list of skill names and descriptions. Click again to collapse.

## Installing plugins from a marketplace

1. Click **+ Install plugin** (right of the bulk-actions row). The install panel slides open.
2. Select a marketplace from the dropdown. The list populates from `~/.claude/plugins/known_marketplaces.json`.
3. Browse plugins. Each row shows name, version, description, and keyword tags.
   - `✓ local` — already installed for your user
   - `✓ global` — installed system-wide
4. Click **Install** on a plugin you want. The server runs `claude plugin install <id> --scope local` in the background.
5. On success the plugin list and marketplace panel both refresh automatically.

> If `claude` is not on `PATH` the error appears inline in the plugin row at install time, not at startup.

## Live updates

A green dot in the header confirms the SSE connection is live. The UI refreshes automatically whenever:

- `.claude/settings.local.json` changes on disk
- `~/.claude/plugins/installed_plugins.json` changes on disk

No manual page reload is needed. If the dot turns amber, the browser is reconnecting (3-second back-off); it will recover automatically.

## Mock mode

If `~/.claude/plugins/installed_plugins.json` does not exist, the server returns built-in mock data. A banner in the UI indicates mock mode. All toggle and localize actions still work against the mock state for the duration of the session, but nothing is persisted to a real plugins file.

## Troubleshooting

### Port already in use

```
OSError: [Errno 98] Address already in use
```

Either pass a different port (`python3 server.py 8080`) or find and stop the process holding port 7779:

```bash
# macOS / Linux
lsof -i :7779

# Windows PowerShell
netstat -ano | Select-String ":7779"
```

### `[WinError 10053]` in the terminal (Windows)

This is a benign Windows networking noise — the browser closed a connection before the server finished reading it. It does not affect functionality and is suppressed by the server. See the README Troubleshooting section for details.

### Changes not reflected in Claude Code

Settings take effect on the next Claude Code session. If a session is already running, restart it (close and reopen the terminal / IDE window where Claude Code is active).
