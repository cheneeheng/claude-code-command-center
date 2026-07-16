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
  `git-sync/`) with its own README, prompt, and installer. The two daily schedulers share one
  parameterized prepare/trigger implementation in `lib/` (`daily-digest-prepare` /
  `daily-digest-trigger`, invoked with the scheduler name).
- Two run mechanisms per scheduler (1-3): **cron** (Task Scheduler / cron calls `claude --print`,
  consuming programmatic credit) and **skill** (on-demand `/session-digest-<name>` from inside a
  Claude Code session in the meta repo, using the interactive session). The skill mechanism exists
  for when programmatic usage is limited.
- Both mechanisms consume the same **prepare** script: it stages per-job inputs plus
  `manifest.json` under `$C4_CLAUDE_META_DIR/.claude/scheduled-session-digests/<scheduler>/`
  (gitignored, reset per run, deleted by the consumer when done). The cron trigger loops the
  manifest through `claude --print` (paths substituted into the prompt template's
  `{{INPUT_FILE}}`/`{{OUTPUT_FILE}}` placeholders); the skill fans it out to subagents.
- Each scheduler tracks progress in `.claude/<scheduler>-cursor` (Unix-epoch mtime of the newest
  source file fully handled). Consumers advance it only over verified outputs, so a crash retries
  exactly the unprocessed work.
- `skills/` holds the installable skills; they are copied to `$C4_CLAUDE_META_DIR/.claude/skills/`.
- `git-sync` stages, date-stamped commits, and pushes `claude-meta` after each run.

## Invariants — do not break these

- **Each of the four schedulers keeps its own README under its sub-folder.** This is a sanctioned
  exception to the one-README-per-member rule (see the root CLAUDE.md). Do not collapse them into
  the top README.
- **`git-sync` is the only writer of git history in `claude-meta`** and is invoked by the other
  schedulers — do not duplicate commit/push logic into the digest scripts.
- **The prepare scripts are the single owner of scan/filter/stage logic.** Triggers and skills
  consume the manifest; never duplicate the discovery logic back into a consumer.
- **All transient files live under `.claude/scheduled-session-digests/<scheduler>/`** in the meta
  repo (gitignored) and are deleted by the consumer — no temp files in the scripts dir, `/tmp`, or
  anywhere else. Cursor files are state, not temp: they stay at `.claude/<scheduler>-cursor`,
  outside the staging dir.
- **Cursors advance only over verified outputs** (oldest-first, stopping at the first failure) so
  crashed or failed jobs are retried. Do not advance a cursor past work that produced no output.
- **Honour `$C4_CLAUDE_META_DIR`** for the meta-repo location.
- **Keep the Windows (PowerShell/Task Scheduler) and Linux (Bash/cron) paths behaviourally
  equivalent.** That includes epoch handling: whole seconds, truncated, on both platforms.
- The daily skills act as coordinators (prepare stages per-chat inputs → one subagent per chat →
  cursor → `git-sync`); the weekly skill harvests collected lessons in a single pass. Preserve that
  fan-out shape.

## Conventions

- PowerShell + Bash; `claude` and `git` on PATH required (Linux also needs `jq`). The `VERSION`
  file tracks this component's release.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
