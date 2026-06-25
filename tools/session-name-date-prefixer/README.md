# session-name-date-prefixer

Auto-injects a dated `--name <dir>-<timestamp>` into the `claude` CLI when you don't pass one,
so your session history is easy to browse.

It wraps the `claude` invocation: placed on `PATH` ahead of the real binary, it passes every
argument through unchanged except that it prepends `--name <cwd>-<yyMMddHHmm>` when `--name`/`-n`
is absent.

| File | Description |
|------|-------------|
| `CC-Inject-Date-To-Session-Name.ps1` | The PowerShell wrapper. |
| `CC-Inject-Date-To-Session-Name-Setup.ps1` | Installer/uninstaller. Install copies the wrapper into `%LOCALAPPDATA%\…` and prepends that dir to the user `PATH`; uninstall reverses both. |
| `cc_inject_date_to_session_name.sh` | Bash equivalent of the wrapper (Linux/macOS). |
| `cc_inject_date_to_session_name_setup.sh` | Bash installer/uninstaller. |

## Quick start

**Windows**
```powershell
.\CC-Inject-Date-To-Session-Name-Setup.ps1                     # install
.\CC-Inject-Date-To-Session-Name-Setup.ps1 -Action uninstall   # remove
# open a new terminal — done
```

**Linux/macOS**
```bash
bash cc_inject_date_to_session_name_setup.sh             # install
bash cc_inject_date_to_session_name_setup.sh uninstall   # remove
```
