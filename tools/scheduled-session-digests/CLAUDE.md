# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Unattended Claude Code automations that run on a schedule and write output to a shared local git
repo (`claude-meta`), optionally pushed to a remote. Four independently installable schedulers:
`daily-summary`, `daily-lessons`, `weekly-lessons`, and `git-sync` (called by the other three).
Both Windows (PowerShell + Task Scheduler) and Linux (Bash + cron) are supported.

## Running

See the top README.md and each sub-folder's README for full usage. Install/uninstall is interactive
via `setup.ps1` (Windows) / `setup.sh` (Linux); it prompts for the `claude-meta` dir and lets you
pick, per scheduler, a cron mechanism and/or a skill mechanism.

## Architecture

- Each scheduler lives in its own folder (`daily-summary/`, `daily-lessons/`, `weekly-lessons/`,
  `git-sync/`) with its own README, scripts, and (where applicable) skill.
- Two run mechanisms per scheduler (1–3): **cron** (Task Scheduler / cron calls `claude --print`,
  consuming programmatic credit) and **skill** (on-demand `/session-digest-<name>` from inside a
  Claude Code session in the meta repo, using the interactive session). The skill mechanism exists
  for when programmatic usage is limited.
- `skills/` holds the installable skills; they are copied to `$C4_CLAUDE_META_DIR/.claude/skills/`.
- `git-sync` stages, date-stamped commits, and pushes `claude-meta` after each run.

## Invariants — do not break these

- **Each of the four schedulers keeps its own README under its sub-folder.** This is a sanctioned
  exception to the one-README-per-member rule (see the root CLAUDE.md). Do not collapse them into
  the top README.
- **`git-sync` is the only writer of git history in `claude-meta`** and is invoked by the other
  schedulers — do not duplicate commit/push logic into the digest scripts.
- **Honour `$C4_CLAUDE_META_DIR`** for the meta-repo location.
- **Keep the Windows (PowerShell/Task Scheduler) and Linux (Bash/cron) paths behaviourally
  equivalent.**
- The daily skills act as coordinators (stage per-chat inputs → one subagent per chat → `git-sync`);
  the weekly skill harvests collected lessons in a single pass. Preserve that fan-out shape.

## Conventions

- PowerShell + Bash; `claude` and `git` on PATH required (Linux also needs `jq`). The `VERSION`
  file tracks this component's release.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
