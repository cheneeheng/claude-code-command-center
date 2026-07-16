# scheduled-session-digests

Unattended Claude Code automations that run on a schedule. Output is written to a
shared local git repo (`claude-meta`, located by `$C4_CLAUDE_META_DIR`), which can
optionally be pushed to a remote.

| # | Scheduler | Default trigger | What it does |
|---|-----------|-----------------|--------------|
| 1 | [daily-summary](daily-summary/) | 02:00 daily | Summarises each new Claude Code chat, one `.md` per session |
| 2 | [daily-lessons](daily-lessons/) | 03:00 daily | Extracts lessons learned from each new chat, one `.md` per session |
| 3 | [weekly-lessons](weekly-lessons/) | Sunday 02:00 | Distils the week's per-session lessons into a master file |
| 4 | [git-sync](git-sync/) | called by 1, 2, and 3 | Stages, commits (date-stamped), and pushes `claude-meta` after each run |

Trigger times, day of week, and session filter thresholds are set interactively
during install; defaults are shown above. Both Windows (PowerShell + Task
Scheduler) and Linux (Bash + cron) are supported.

---

## Two ways to run each scheduler

Each scheduler (1–3) can be installed as either — or both — of:

| Mechanism | How it runs | Cost |
|-----------|-------------|------|
| **cron** | Unattended on a schedule (Task Scheduler / cron). The trigger calls `claude --print`. | Consumes programmatic credit |
| **skill** | On demand from inside a Claude Code session opened in the meta repo, via `/session-digest-<name>`. | Uses your interactive session |

The skill mechanism exists for when programmatic (`claude --print`) usage is
limited. The daily skills act as coordinators — they fan one subagent out per
chat; the weekly skill is a single analysis pass.

Install presents a split list so you can pick any combination, e.g. skills for
daily, cron for weekly. Skills are installed to
`$C4_CLAUDE_META_DIR/.claude/skills/` and are discoverable when you run Claude
Code with the meta repo as the working directory.

---

## How a run works

Both mechanisms share the same pipeline; only the step that calls Claude differs.

1. **Prepare** (`daily-digest-prepare.{ps1,sh}` for the dailies,
   `weekly-lessons-prepare.{ps1,sh}` for the weekly) scans for new work since the
   scheduler's **cursor** and stages input files plus a `manifest.json` under
   `$C4_CLAUDE_META_DIR/.claude/scheduled-session-digests/<scheduler>/`
   (gitignored, reset on every run).
2. **Consume** — the cron trigger loops each staged job through `claude --print`;
   the skill fans the jobs out to subagents. Either way, Claude writes each
   digest directly to its final output path.
3. **Advance the cursor** — `.claude/<scheduler>-cursor` records the mtime (Unix
   epoch) of the newest source file whose output was verified. A crash or failed
   job leaves the cursor behind it, so exactly the unprocessed work is retried
   next run.
4. **Commit** — `git-sync` makes one date-stamped commit (and pushes if a remote
   is configured), then the staging directory is deleted.

---

## Quick start

```powershell
# Windows
git clone <this-repo>
cd tools\scheduled-session-digests
.\setup.ps1
```

```bash
# Linux
git clone <this-repo>
cd tools/scheduled-session-digests
bash setup.sh
```

The CLI prompts for the `claude-meta` directory, initialises it as a git repo,
and installs whichever schedulers and mechanisms you choose from a split list.
For each cron scheduler you can customise the run time and (for daily
schedulers) the minimum session length thresholds — press Enter to accept the
defaults. It also handles uninstall, grouped by mechanism.

---

## Requirements

| Platform | Requirements |
|----------|-------------|
| Windows  | PowerShell 5+, `claude` CLI on PATH, `git` on PATH |
| Linux    | Bash 4+, `claude` CLI on PATH, `git` on PATH, `jq` on PATH |

---

## The claude-meta repo

All schedulers write into `$C4_CLAUDE_META_DIR` (default: `~/claude-meta`):

```
claude-meta/
  daily-summaries/     <- one .md per chat session (daily-summary)
  lessons-learned/     <- one .md per chat session (daily-lessons)
  master-lessons/      <- MASTER_LESSONS_LEARNED.md (weekly-lessons)
  logs/                <- per-run script logs
  .claude/
    scripts/           <- prepare + trigger scripts, prompts, and git-sync
    skills/            <- interactive scheduler skills (skill mechanism)
    <scheduler>-cursor <- per-scheduler progress cursor (Unix epoch)
    scheduled-session-digests/  <- transient staging (gitignored, auto-cleaned)
    settings.json      <- Claude tool permissions for unattended runs
```

---

## Docs

- [daily-summary — how it works, output format, manual run](daily-summary/README.md)
- [daily-lessons — how it works, output format, manual run](daily-lessons/README.md)
- [weekly-lessons — how it works, output format, manual run](weekly-lessons/README.md)
- [git-sync — usage, adding a remote](git-sync/README.md)

---

## Uninstall

```powershell
# Windows
.\setup.ps1   # choose [2] Uninstall
```

```bash
# Linux
bash setup.sh   # choose [2] Uninstall
```
