# session-name-date-prefixer

Names each new Claude Code session `<folder>-<yyMMddHHmm>`, so your session history is easy to
browse. A session you start with `--name` keeps the name you gave it.

It is a `SessionStart` hook in your `settings.json`. The setup script adds it, and removes only
it on uninstall, leaving your other settings and hooks alone.

| File | Description |
|------|-------------|
| `session-name-date-prefixer-setup.ps1` | Windows installer/uninstaller. Writes a PowerShell version of the hook. |
| `session-name-date-prefixer-setup.sh` | Linux/macOS installer/uninstaller. Writes a bash version of the hook. Needs `jq`. |
| `tests/smoke.sh` | Installs, runs and uninstalls the hook against a temp config dir. |

## Quick start

**Windows**
```powershell
.\session-name-date-prefixer-setup.ps1                      # install
.\session-name-date-prefixer-setup.ps1 -Action uninstall    # remove
.\session-name-date-prefixer-setup.ps1 -ClaudeDir D:\claude # another config dir
```

**Linux/macOS**
```bash
bash session-name-date-prefixer-setup.sh                         # install
bash session-name-date-prefixer-setup.sh uninstall               # remove
bash session-name-date-prefixer-setup.sh --claude-dir ~/.claude2 # another config dir
```

The next session you start picks the hook up. No new terminal is needed.

## Upgrading from the wrapper

Versions before 0.3.0 put a `claude` wrapper on your PATH. Install and uninstall both remove it:
on Windows the `%LOCALAPPDATA%\claude-automation\cc-inject-date-to-session-name` folder and its
user PATH entry, on Linux/macOS `~/.local/bin/claude` when it is the wrapper. The rc line that put
`~/.local/bin` on PATH stays, because other tools live there too.
