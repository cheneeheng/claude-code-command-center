# scheduled-session-digests

Unattended Claude Code automations that run on a schedule. Output is written to a
shared local git repo (`claude-meta`), which can optionally be pushed to a remote.

| # | Scheduler | Default trigger | What it does |
|---|-----------|-----------------|--------------|
| 1 | [daily-summary](daily-summary/) | 02:00 daily | Reads each Claude Code chat from the last run, summarises it with Claude, writes one `.md` per session |
| 2 | [daily-lessons](daily-lessons/) | 03:00 daily | Reads each Claude Code chat from the last run, extracts lessons learned via the `ceh-lessons-learned` skill, writes one `.md` per session |
| 3 | [weekly-lessons](weekly-lessons/) | Sunday 02:00 | Reads per-session lessons files written by daily-lessons, distils project-generic lessons into a master file |
| 4 | [git-sync](git-sync/) | called by 1, 2, and 3 | Stages, commits (date-stamped), and pushes `claude-meta` after each run |

Trigger times, day of week, and session filter thresholds are set interactively during install. Defaults are shown above.

Both Windows (PowerShell + Task Scheduler) and Linux (Bash + cron) are supported.

---

## Two ways to run each scheduler

Each scheduler (1–3 above) can be installed as either — or both — of:

| Mechanism | How it runs | Cost |
|-----------|-------------|------|
| **cron** | Unattended on a schedule (cron / Task Scheduler). The trigger calls `claude --print`. | Consumes programmatic credit |
| **skill** | On demand from inside a Claude Code session opened in the meta repo, via `/session-digest-<name>`. A prepare script stages the work and the session fans it out to subagents. | Uses your interactive session |

The skill mechanism exists for when programmatic (`claude --print`) usage is limited.
The daily skills act as a coordinator — stage per-chat inputs, spawn one subagent per
chat, then `git-sync`. The weekly skill harvests the collected lessons in a single pass.

Install presents a split list so you can pick any combination, e.g. skills for daily,
cron for weekly. Skills are installed to `$CLAUDE_META_DIR/.claude/skills/` and are
discoverable when you run Claude Code with the meta repo as the working directory.

See [CHANGELOG.md](CHANGELOG.md) for release history.

---

## Quick start

```powershell
# Windows
git clone <this-repo>
cd scheduled-session-digests
.\setup.ps1
```

```bash
# Linux
git clone <this-repo>
cd scheduled-session-digests
bash setup.sh
```

The CLI prompts for the `claude-meta` directory, initialises it as a git repo,
and installs whichever schedulers and mechanisms you choose from a split list
(skill and/or cron per scheduler — see below). For each cron scheduler you can
customise the run time and (for daily schedulers) the minimum session length
thresholds — press Enter to accept the defaults. It also handles uninstall,
grouped by mechanism.

---

## Requirements

| Platform | Requirements |
|----------|-------------|
| Windows  | PowerShell 5+, `claude` CLI on PATH, `git` on PATH |
| Linux    | Bash 4+, `claude` CLI on PATH, `git` on PATH, `jq` on PATH |

---

## Docs

- [daily-summary — how it works, output format, manual run](daily-summary/README.md)
- [daily-lessons — how it works, output format, manual run](daily-lessons/README.md)
- [weekly-lessons — configuration, output format, manual run](weekly-lessons/README.md)
- [git-sync — usage, adding a remote, claude-meta structure](git-sync/README.md)

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
