# claude-automation

Quality-of-life scripts and tooling for Claude Code on Windows. Four independent modules — pick what you need.

---

## cc-statusline

Live token/cost dashboard and terminal statusline hook for Claude Code sessions. The statusline hook scripts live in the folder root; the dashboard server and its scheduled-task scripts live in the `cc-statusline-dashboard-server/` subfolder.

| File | Description |
|------|-------------|
| `statusline.ps1` | Claude Code `StatusLine` hook (PowerShell). Reads the JSON blob piped by Claude Code on each turn, prints a colour-coded one-liner (`model \| context bar \| runtime \| cost \| 5H rate \| 7D rate`), and appends a compact record to `~/.claude/statusline/<project>/<session>.jsonl` for the server to consume. |
| `statusline.sh` | Same hook as `statusline.ps1` but for bash/Linux/macOS. Requires `jq`. |
| `statusline.py` | Stdlib Python port of the hook. UTF-8-safe stdin/stdout (works when piped on Windows), same colour-coded output and per-project `<session>.jsonl` logging as the shell versions. |
| `cc-statusline-dashboard-server/cc-statusline-dashboard-server.py` | Stdlib-only HTTP server entrypoint (default port 8080). Reads `~/.claude/projects/**/*.jsonl` for historical session data and `~/.claude/statusline/**/*.jsonl` for live rate-limit data. Serves a single-page dashboard with token charts, cost breakdown by model, rate-limit gauges, and a session table. No pip dependencies. Logic is split across sibling modules by data source: `dashboard_config.py` (config + model pricing/family), `session_stats.py` (transcript parsing → tokens + estimated cost), `live_statusline.py` (statusline logs → rate limits + actual cost), `merge.py` (reconciles the two into the API payload), `dashboard_server.py` (HTTP handler), `dashboard.html` (page shell), `dashboard.css` (styles), and `dashboard.js` (UI rendering logic). See `cc-statusline-dashboard-server/README.md` for the data-flow walkthrough. |
| `cc-statusline-dashboard-server/cc-statusline-dashboard-server-start-once.ps1` | Guard wrapper: checks whether port 8080 is already in use before launching the server, so it is safe to call repeatedly (e.g. from a scheduled task). |
| `cc-statusline-dashboard-server/cc-statusline-dashboard-server-setup.ps1` | Combined install/uninstall. Install registers a Windows Task Scheduler task (`\ClaudeAutomation\StartStatuslineServer`) that runs the guard wrapper at logon and on resume from sleep/hibernate; uninstall unregisters it. No elevation required. Accepts `-Action install\|uninstall` (default `install`). |

**Quick start (Windows):**
1. Add the `StatusLine` hook to `~/.claude/settings.json` pointing at `statusline.ps1`.
2. Run `cc-statusline-dashboard-server/cc-statusline-dashboard-server-setup.ps1` to start the server automatically.  
   Alternatively run `python cc-statusline-dashboard-server/cc-statusline-dashboard-server.py` to start the server immediately.
3. Open `http://localhost:8080`.

---

## cc-inject-date-to-session-name

Intercepts the `claude` CLI invocation to auto-inject a `--name <dir>-<timestamp>` session name when none is supplied, making session history easier to browse.

| File | Description |
|------|-------------|
| `CC-Inject-Date-To-Session-Name.ps1` | The wrapper script. Placed on `PATH` before the real `claude` binary; passes all args through unchanged except that it prepends `--name <cwd>-<yyMMddHHmm>` when `--name`/`-n` is absent. |
| `CC-Inject-Date-To-Session-Name-Setup.ps1` | Combined installer/uninstaller. `install` (default) copies the wrapper to `%LOCALAPPDATA%\claude-automation\cc-inject-date-to-session-name\claude.ps1` and prepends that directory to the user `PATH`; `uninstall` reverses both. |
| `cc_inject_date_to_session_name.sh` | Bash equivalent of the wrapper for Linux/macOS. |
| `cc_inject_date_to_session_name_setup.sh` | Bash combined installer/uninstaller for the shell wrapper. |

**Quick start (Windows):**
```powershell
.\CC-Inject-Date-To-Session-Name-Setup.ps1            # install
.\CC-Inject-Date-To-Session-Name-Setup.ps1 -Action uninstall
# Open a new terminal — done.
```

**Quick start (Linux/macOS):**
```bash
bash cc_inject_date_to_session_name_setup.sh           # install
bash cc_inject_date_to_session_name_setup.sh uninstall
```

---

## cc-sync-claude-settings-and-claude-devcontainer-settings

Keeps two `settings.json` files in sync (e.g. `~/.claude/settings.json` and `~/.claude_devcontainer/settings.json`), always copying from the newer file to the older while preserving machine-specific keys in the destination.

| File | Description |
|------|-------------|
| `cc-sync-claude-settings-and-claude-devcontainer-settings.ps1` | Core sync script. Compares `LastWriteTime` of two JSON files, deep-clones the newer one, strips `ExcludePaths` keys, restores their values from the destination, and writes the result. Configurable exclude list (default: `statusLine.command`). |
| `cc-sync-claude-settings-and-claude-devcontainer-settings-setup.ps1` | Combined install/uninstall. Install registers a Task Scheduler task (`\ClaudeAutomation\SyncClaudeSettings`) that runs on a configurable interval via a hidden VBS launcher. Daily anchor + repetition pattern + `StartWhenAvailable`/`WakeToRun` so missed runs fire on next wake and the schedule never expires. Run as Administrator. Accepts `-Action install\|uninstall` (default `install`) and `-IntervalMinutes <int>` (default `15`, range `1–1439`). Uninstall unregisters the task and removes the hidden launcher. |
| `cc-sync-claude-settings-and-claude-devcontainer-settings-hidden.vbs` | Generated by the setup script on install. Launches the PowerShell sync script with no visible window. Do not edit manually. |

**Quick start (Windows):**
```powershell
# As Administrator — install with default 15-minute interval:
.\cc-sync-claude-settings-and-claude-devcontainer-settings-setup.ps1

# Custom interval (e.g. every 5 minutes):
.\cc-sync-claude-settings-and-claude-devcontainer-settings-setup.ps1 -IntervalMinutes 5

# Uninstall:
.\cc-sync-claude-settings-and-claude-devcontainer-settings-setup.ps1 -Action uninstall
```

---

## cc-sync-claude-md-and-claude-devcontainer-md

Keeps `CLAUDE.md` in sync between `~/.claude/` and `~/.claude_devcontainer/`, always copying from the newer file to the older. Plain-text equivalent of `cc-sync-claude-settings-and-claude-devcontainer-settings` — no merge logic needed.

| File | Description |
|------|-------------|
| `cc-sync-claude-md-and-claude-devcontainer-md.ps1` | Core sync script. Compares `LastWriteTime` of the two `CLAUDE.md` files and copies the newer one over the older. |
| `cc-sync-claude-md-and-claude-devcontainer-md-setup.ps1` | Combined install/uninstall. Install registers a Task Scheduler task (`\ClaudeAutomation\SyncClaudeMd`) that runs on a configurable interval via a hidden VBS launcher. Daily anchor + repetition pattern + `StartWhenAvailable`/`WakeToRun` so missed runs fire on next wake and the schedule never expires. Run as Administrator. Accepts `-Action install\|uninstall` (default `install`) and `-IntervalMinutes <int>` (default `15`, range `1–1439`). Uninstall unregisters the task and removes the hidden launcher. |
| `cc-sync-claude-md-and-claude-devcontainer-md-hidden.vbs` | Generated by the setup script on install. Launches the PowerShell sync script with no visible window. Do not edit manually. |

**Quick start (Windows):**
```powershell
# As Administrator — install with default 15-minute interval:
.\cc-sync-claude-md-and-claude-devcontainer-md-setup.ps1

# Custom interval (e.g. every 30 minutes):
.\cc-sync-claude-md-and-claude-devcontainer-md-setup.ps1 -IntervalMinutes 30

# Uninstall:
.\cc-sync-claude-md-and-claude-devcontainer-md-setup.ps1 -Action uninstall
```
