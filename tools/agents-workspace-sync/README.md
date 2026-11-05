# agents-workspace-sync

Commits and pushes a list of `.agents_workspace` git repos once a day, unattended.

Agent working notes (decision logs, handoffs, architecture docs, plans) accumulate across
several projects and are easy to leave uncommitted for weeks. This tool walks a configured
list of `.agents_workspace` repos and, for each one, pulls remote changes (fast-forward
only), stages everything, makes one date-stamped commit, and pushes.

| | |
|---|---|
| **Default trigger** | 04:00 daily (Task Scheduler `\ClaudeAutomation\agents-workspace-sync\agents-workspace-sync`, or cron) |
| **Install dir** | `~/.claude-command-center/agents-workspace-sync/`: the worker, `VERSION`, `config.json`, `logs/` |
| **Config** | `~/.claude-command-center/agents-workspace-sync/config.json` |
| **Logs** | `~/.claude-command-center/agents-workspace-sync/logs/<yyyy>/<MM>/<timestamp>_agents-workspace-sync.log` (Linux cron output also goes to `cron.log` there) |
| **Needs** | `git` on PATH. Linux also needs `jq`. No `claude` CLI — this tool never calls Claude. |

---

## Each path must be its own git repo

A configured path must be a git repo **in its own right** — it has its own `.git`, and it is
the repo's top level. This is checked on every run; a path that fails is logged as an error
and skipped, and the run exits `2`.

That check is the point of the tool, not a formality. If a `.agents_workspace` folder is just
a tracked subdirectory of an outer project repo, then `git -C <path> add -A` walks *up* to the
outer `.git` and stages **the whole parent project** — every unrelated work-in-progress edit —
then commits and pushes it. Nightly. Across every repo in the list. So the guard runs first:

```
ERROR [C:\...\some-project\.agents_workspace]: not a git repo by itself - it belongs to
C:/.../some-project. Skipping (staging here would commit the parent repo).
```

The test is `git rev-parse --show-prefix`, which is empty only at a repo root. Comparing path
strings would be wrong: git prints `C:/x/y` where Git Bash's `pwd` prints `/c/x/y`, and case,
symlinks, and 8.3 short names all differ too.

Setting one up, if you have a `.agents_workspace` that is not yet standalone:

```bash
cd <project>/.agents_workspace
git init && git remote add origin <url>
# and in the parent project: git rm -r --cached .agents_workspace
#                            echo ".agents_workspace/" >> .gitignore
```

---

## Branches: whatever is checked out, never switched

Each repo is committed and pushed **on the branch it is already on**. The tool never runs
`checkout`, `merge`, or `branch`.

These repos are typically sibling branches of one shared remote — one branch per parent
project, all pushing to the same `agents-workspace` repo — so merging into a default branch
would be actively wrong. It also means the tool is safe to run against a repo you are working
in right now: your HEAD does not move.

- A branch with no upstream is published with `push -u <remote> <branch>`.
- A branch already level with its upstream is not pushed at all.
- A detached HEAD is logged as an error and skipped.

---

## Config

```json
{
  "scheduleTime": "04:00",
  "repos": [
    "C:/Users/me/WorkLocal/00_Project/agent-skills/.agents_workspace",
    "C:/Users/me/WorkLocal/00_Project/other-project/.agents_workspace"
  ]
}
```

Written by the setup script; edit it directly afterwards to add or drop repos — no reinstall
needed, the worker re-reads it on every run. A parent-project path is also accepted (the tool
appends `.agents_workspace` when the parent contains one), so both spellings work.

---

## Install

```powershell
# Windows
.\agents-workspace-sync-setup.ps1
```

```bash
# Linux
bash agents-workspace-sync-setup.sh
```

Both prompt for the run time and the repo list (pre-filled from an existing config), validate
every path up front, install the worker into the install dir (`-InstallDir` / `--install-dir`
to pick another), and register the daily task. Or install it through the umbrella:
`setup/command-center.ps1` (descriptor: `agents-workspace-sync`, requires a `repos` config key).

Upgrading from 0.1.x, which installed into `$C4_CLAUDE_META_DIR/.claude/scripts/` (default
`~/claude-meta`): install pre-fills the repo list from the old config, then deletes the old
worker, `VERSION` and config there. Those files were tracked in the claude-meta repo, so its
git-sync commits the deletions. Old logs under `<meta>/logs/` stay where they are.

Uninstall removes the task, the installed worker, and the config; the logs and every target
repo are left untouched:

```powershell
.\agents-workspace-sync-setup.ps1 -Action uninstall   # add -KeepConfig to keep the repo list
```

```bash
bash agents-workspace-sync-setup.sh --action uninstall   # --keep-config
```

---

## Manual run

```powershell
& "$HOME\.claude-command-center\agents-workspace-sync\agents-workspace-sync.ps1" -DryRun
& "$HOME\.claude-command-center\agents-workspace-sync\agents-workspace-sync.ps1"
& "$HOME\.claude-command-center\agents-workspace-sync\agents-workspace-sync.ps1" -Repos "C:\p\a\.agents_workspace"
```

```bash
~/.claude-command-center/agents-workspace-sync/agents-workspace-sync.sh --dry-run
~/.claude-command-center/agents-workspace-sync/agents-workspace-sync.sh
~/.claude-command-center/agents-workspace-sync/agents-workspace-sync.sh /p/a/.agents_workspace
```

`--dry-run` / `-DryRun` reports the branch and pending change count per repo and touches
nothing. Explicit repo paths bypass the config file. The worker reads `config.json` and writes
`logs/` next to itself, so run the installed copy: one run from the checkout logs into
`logs/` there (git-ignored).

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Every repo synced |
| `1` | Fatal — config missing or unparseable, or no repos configured |
| `2` | Ran, but one or more repos failed; the rest still synced |

One bad repo never aborts the batch. Sample log:

```
[2026-08-31 04:00:01] [agents-workspace-sync] Start - 3 repo(s).
[2026-08-31 04:00:02] [agents-workspace-sync] [agent-skills] Committed 4 file(s) on agent-skills.
[2026-08-31 04:00:04] [agents-workspace-sync] [agent-skills] Pushed 1 commit(s) to agent-skills.
[2026-08-31 04:00:05] [agents-workspace-sync] [other-project] Nothing to commit.
[2026-08-31 04:00:05] [agents-workspace-sync] [other-project] Up to date with upstream - nothing to push.
[2026-08-31 04:00:06] [agents-workspace-sync] ERROR [C:\...\third\.agents_workspace]: not a git repo by itself - ...
[2026-08-31 04:00:06] [agents-workspace-sync] Done - 2 ok, 1 failed. Log: ...
```

---

## Unattended-run notes

- **No credential prompts.** The worker sets `GIT_TERMINAL_PROMPT=0` and
  `GIT_SSH_COMMAND="ssh -o BatchMode=yes"` (unless already set), so a missing credential or a
  passphrase-protected key fails the push and is logged, rather than hanging the task until it
  is killed. Use an ssh-agent key or a credential helper that works without a prompt.
- **Push failures are not retried in-run.** The commit is already made locally, so the next
  day's run pushes it along with whatever is new.
- **Pull is fast-forward only.** A branch with an upstream runs `git pull --ff-only` before
  staging. If that fails (local and remote diverged, or incoming changes touch files you have
  uncommitted edits in) the repo is logged as a failure and skipped. The tool never merges or
  rebases, so it never leaves a repo mid-conflict.
- **The 15-minute task limit** is generous for a handful of pushes and exists so a wedged
  network call dies rather than lingering.
