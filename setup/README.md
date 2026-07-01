# setup — unified installer for the Command Center tools

One entry point to install, uninstall, and track the repo's installable `tools/` members,
instead of running each tool's setup script by hand and guessing what is currently installed.

It is a **thin orchestrator**: it never reimplements a tool's install logic, it delegates to each
member's own setup script and records the outcome in a per-machine **manifest**.

## What it manages

| Member | What "install" does |
|--------|---------------------|
| `session-name-date-prefixer` | Adds a `claude` wrapper to your user PATH |
| `statusline-hook` | Copies the hook into `~/.claude/` and wires `statusLine` in `settings.json` |
| `file-sync` | Registers Task Scheduler jobs to keep folder pairs in sync (needs config) |
| `scheduled-session-digests` | Registers digest schedulers (skills and/or scheduled tasks) |

Apps, `usage-report`, and libs are **not** managed here — they are run on demand, not installed.

## Usage

```powershell
# from the repo root
./setup/command-center.ps1 list       # members, versions, whether config is present
./setup/command-center.ps1 status     # manifest vs what's actually on this machine

./setup/command-center.ps1 install -Member statusline-hook
./setup/command-center.ps1 install -All            # members listed in config.json
./setup/command-center.ps1 uninstall -Member file-sync
./setup/command-center.ps1 uninstall -All
```

`install -All` installs only the members you opted in by giving them an entry in `config.json`
(even an empty `{}`); members absent from the config are **skipped** (with a note), as are members
present but still missing their required config — the run never fails on a skip. Use
`install -Member <name>` to install a single member with defaults without adding it to the config.
Only `file-sync` requires config (folder pairs). `file-sync` and `scheduled-session-digests`
register Windows Task Scheduler jobs — run an elevated shell if their setup scripts ask for it.

## Config

Copy the template and fill it in (strict JSON — drop the `//` comments):

```powershell
mkdir ~/.claude-command-center -Force
cp ./setup/command-center.config.example.jsonc ~/.claude-command-center/config.json
# edit config.json
```

Override the path with `-Config <path>`. Under `-All`, only members with an entry here are
installed; a listed member that omits optional keys uses its defaults (e.g. `statusline-hook`
→ `ps1`, digests → skill-based under `~/claude-meta`). To install an unlisted member with its
defaults, target it directly with `install -Member <name>`.

## Manifest

State lives at `~/.claude-command-center/manifest.json` (created on first install). It records, per
member: `installed`, `installed_at`, `version`, and the params used — `file-sync` and digest
uninstalls **replay** those recorded params, so the manifest is what makes a later `uninstall` work.

`status` compares the manifest against live detection (PATH entry, `settings.json` key, scheduled
tasks). Yellow = present on the machine but not in the manifest (e.g. installed by hand before);
Red = recorded as installed but no longer detected.

## Files

- `command-center.ps1` — the CLI (`list` / `status` / `install` / `uninstall`)
- `registry.ps1` — catalog of managed members (one descriptor each); add a member here
- `command-center.config.example.jsonc` — config template

## Adding a member

Append a descriptor to `registry.ps1` with the member's `SetupScript`, `Install`/`Uninstall`
script blocks (delegating to that script), a `Detect` probe, and any `RequiredConfig` keys.
Nothing else needs to change.
