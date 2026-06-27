# session-name-date-prefixer

Auto-injects a dated `--name <dir>-<timestamp>` into the `claude` CLI when you don't pass one,
so your session history is easy to browse.

It wraps the `claude` invocation: placed on `PATH` ahead of the real binary, it passes every
argument through unchanged except that it prepends `--name <cwd>-<yyMMddHHmm>` when `--name`/`-n`
is absent.

| File | Description |
|------|-------------|
| `session-name-date-prefixer.ps1` | The PowerShell wrapper. |
| `session-name-date-prefixer-setup.ps1` | Installer/uninstaller. Install copies the wrapper into `%LOCALAPPDATA%\…` and prepends that dir to the user `PATH`; uninstall reverses both. |
| `session-name-date-prefixer.sh` | Bash equivalent of the wrapper (Linux/macOS). |
| `session-name-date-prefixer-setup.sh` | Bash installer/uninstaller. |

## Quick start

**Windows**
```powershell
.\session-name-date-prefixer-setup.ps1                     # install
.\session-name-date-prefixer-setup.ps1 -Action uninstall   # remove
# open a new terminal — done
```

**Linux/macOS**
```bash
bash session-name-date-prefixer-setup.sh             # install
bash session-name-date-prefixer-setup.sh uninstall   # remove
```
