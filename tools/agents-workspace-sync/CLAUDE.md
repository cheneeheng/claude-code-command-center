# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A daily unattended job that commits and pushes a configured list of `.agents_workspace` git
repos. Pure git plumbing — it never calls the `claude` CLI and has no cursor, no staging dir,
and no transcript scanning. It borrows the digests' logging and install shape, nothing else.

## Running

See `README.md`. Install via `agents-workspace-sync-setup.ps1` / `.sh`, or through
`setup/command-center.ps1` (descriptor `agents-workspace-sync`, `RequiredConfig = @('repos')`).

## Architecture

- `agents-workspace-sync.ps1` / `.sh` — the worker. Reads the config, loops the repos, and for
  each: validates, `add -A`, commit, push. Installed into `$C4_CLAUDE_META_DIR/.claude/scripts/`.
- `agents-workspace-sync-setup.ps1` / `.sh` — install/uninstall. Writes the config, copies the
  worker, registers the daily Task Scheduler task (`\ClaudeAutomation\agents-workspace-sync`)
  or crontab entry.
- Config: `$C4_CLAUDE_META_DIR/.claude/scripts/agents-workspace-sync-config.json`
  (`{scheduleTime, repos[]}`), re-read every run so editing it needs no reinstall.
- Logs: `$C4_CLAUDE_META_DIR/logs/<yyyy>/<MM>/<timestamp>_agents-workspace-sync.log`, the same
  layout `scheduled-session-digests` uses.

## Invariants — do not break these

- **Every configured path must be the top level of its own git repo, and that must be checked
  before staging.** The test is `git rev-parse --show-prefix` being empty. Never compare path
  strings: git prints `C:/x/y` where Git Bash's `pwd` prints `/c/x/y`, and case, symlinks, and
  8.3 short names differ too — a string compare rejects every repo on Git Bash. Dropping the
  check is worse: `git -C <nested> add -A` walks up to the outer `.git` and would commit and
  push the entire parent project every night.
- **Never switch branches.** No `checkout`, `merge`, or `branch`. Each repo is committed and
  pushed on whatever branch is checked out — these repos are sibling branches of one shared
  remote, and the tool must be safe to run against a repo someone is working in. This is the
  deliberate difference from `scheduled-session-digests/git-sync`, which *does* merge to the
  default branch because it owns `claude-meta` outright.
- **Never pull, merge, or rebase**, and never force-push. A rejected push is logged and left
  for a human.
- **One repo's failure must not abort the batch.** Log it, count it, continue; exit `2` at the
  end. Exit `1` is reserved for fatal setup problems (no meta dir, no config, no repos).
- **`Log` writes to the PowerShell success stream**, so a function that calls it must not also
  return a value — the two would arrive mixed together and a caller testing the result would be
  testing a non-empty array instead. `Sync-Repo` reports failures through `$script:Failed`.
- **Unattended runs must never block on a prompt.** Keep `GIT_TERMINAL_PROMPT=0` and the
  `BatchMode=yes` `GIT_SSH_COMMAND` default.
- **Keep the PowerShell and Bash workers behaviourally equivalent** — same guards, same log
  wording, same exit codes.
- **Honour `$C4_CLAUDE_META_DIR`** for logs and config; abort when it is unset.

## Conventions

- PowerShell + Bash; `git` on PATH required (Linux also needs `jq` to read the config).
  The `VERSION` file tracks this component's release.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
