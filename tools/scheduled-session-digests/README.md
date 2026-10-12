# scheduled-session-digests

Turns your Claude Code sessions into lessons learned, in the background. Install it once:

- **Every night**, each of your new sessions goes through Claude Code in headless mode
  (`claude --print`) and comes back as one lessons file: what went wrong, and the rule to
  apply next time.
- **Every week**, the new lessons that apply beyond one project are merged into a single
  master file, under categories.
- **Everything lands in a local git repo you own** (`claude-meta`), committed after each run,
  and pushed if you add a remote.

It also keeps a cleaned copy of each session's conversation, so later analyses can still read
sessions that Claude Code has since deleted.

## Quick start

Windows (PowerShell 7.4+):

```powershell
git clone <this repo>; cd <clone>/tools/scheduled-session-digests
pwsh ./lessons.ps1 install
pwsh ./lessons.ps1 run -DryRun
```

Linux (Bash 4+ and `jq`):

```bash
git clone <this repo> && cd <clone>/tools/scheduled-session-digests
bash lessons.sh install
bash lessons.sh run --dry-run
```

You need `claude` and `git` on your PATH. `install` lists every change it is about to make
and asks before it changes anything. `run -DryRun` shows what the first real run would
process, and writes nothing.

## What runs when

| | When | Model | What it does |
|---|---|---|---|
| Daily | 03:00 | `sonnet`, medium effort | One lessons file per new session, in `lessons-learned/<yyyy>/<MM>/` |
| Weekly | Sunday 04:00 | `opus`, medium effort | Adds the week's generic lessons to `master-lessons/MASTER_LESSONS_LEARNED.md` |

One scheduled entry (a Windows task, or a cron line on Linux) wakes up every hour and runs
only what is due. If your machine was asleep or off at 03:00, the run happens at the next
hourly check. The first scheduled run is at the first 03:00 after you install, never right
away.

A session is processed once, as a whole, after it has been quiet for an hour. Sessions with
fewer than 2 of your messages or under 500 characters are skipped. Subagent transcripts are
skipped too: their "user" turns are another agent's prompts, not yours.

## What it costs

Each session is one `claude --print` call, which uses your Claude Code credit. Three limits
keep that bounded:

- **First run.** The very first run covers only the last 7 days. Pass `-All` (`--all`) to go
  further back. That covers every session still on disk, so check `run -DryRun -All` first.
- **Cap.** A scheduled run processes at most 20 sessions. The rest wait for the next hourly
  check.
- **Preview.** A manual run shows how many sessions it will process, and a rough token count,
  then asks before it starts.

If `claude` fails (logged out, usage limit, network), the run stops at once and records the
error. It doesn't count against any session. The next hourly check tries again. The same
goes for a failed commit to the meta repo: `status` shows the error, and the next check
commits what the failed run left uncommitted.

## Commands

Windows spelling first; Bash uses `--kebab-case` (`--meta-dir`, `--dry-run`, ...).

| Command | What it does |
|---|---|
| `install [-MetaDir <p>] [-DailyAt HH:MM] [-WeeklyDay <Day>] [-WeeklyAt HH:MM] [-NoSchedule] [-NoArchive] [-Yes]` | Sets everything up. `-NoSchedule`: manual runs only. `-NoArchive`: skip the one-time archive of sessions already on disk. Safe to run again. |
| `run [-Job daily\|weekly] [-All] [-Since yyyy-mm-dd] [-DryRun] [-Yes]` | Runs a job now (daily by default). |
| `status` | Schedule, next runs, progress, the last run of each job and its error, and given-up sessions. |
| `uninstall [-Purge] [-Yes]` | Removes the schedule and the tool's files. Keeps your lessons, transcripts, logs, and `config.json` unless you pass `-Purge`. Never touches the meta repo itself or its `.git`. |

`-MetaDir` (`--meta-dir`) works with every command. It defaults to `$C4_CLAUDE_META_DIR`, then
`~/claude-meta`.

## Settings

`install` writes `<meta>/.claude/session-lessons/config.json`. Edit it any time:

| Key | Default | Meaning |
|---|---|---|
| `schedule.dailyAt`, `schedule.weeklyDay`, `schedule.weeklyAt` | `03:00`, `Sunday`, `04:00` | When the jobs are due |
| `thresholds.minUserTurns`, `thresholds.minTranscriptChars` | `2`, `500` | Shorter sessions are skipped |
| `firstRunDays` | `7` | How far back the first run looks |
| `maxSessionsPerRun` | `20` | The cap on scheduled runs |
| `maxAttempts` | `3` | Bad answers before a session is given up |
| `settleMinutes` | `60` | How long a session must be quiet first |
| `models.daily`, `models.weekly` | sonnet / opus, medium | Model and effort per job |

## Extractions

The daily job is built around **extractions**: each one is a prompt section and an output
folder in `config.json`. The product ships one, `lessons`. Every session is sent to `claude`
**once**, asking for every extraction it still needs, and the answer is split and filed per
extraction. An extraction added later only processes the sessions that lack its output.

## The transcript archive

Before a session is sent to `claude`, it is cleaned. Only your own messages, Claude's replies,
the questions Claude asked you with your answers, tool calls you rejected, and interruptions
are kept. Tool output and text injected by hooks are dropped. That cleaned copy is kept in
`transcripts/<yyyy>/<MM>/` and committed. Its header names the cleanup rules that made it
(`Cleanup: v1`).

`install` offers a one-time archive of every session still on disk. It makes no `claude`
calls.

## When something fails

- A session whose answer is invalid three times is **given up** and no longer paid for.
  `status` lists it. To retry it, delete its line from `<meta>/.claude/session-lessons/state/given-up.txt`.
- Each run writes a log under `<meta>/logs/<yyyy>/<MM>/`.
- Only one run works on a meta repo at a time. A second one exits at once.

## Privacy

The meta repo holds extracts of your private sessions: lessons, and cleaned transcripts. It
stays on your machine unless you add a git remote. **Before adding one, make sure the remote
repo is private.** From then on, every run pushes.

```bash
git -C ~/claude-meta remote add origin <your private repo>
git -C ~/claude-meta push -u origin HEAD
```

## Upgrading from the previous version

Run `install` as above. It finds the previous version's scheduled tasks, cron lines, scripts,
and interactive skills that point at this meta repo, lists them, and removes them when you
confirm. Files it does not name stay. Your existing lessons and master file stay as they are.
The new version continues from where the old one stopped, and keeps your old schedule and
thresholds. `daily-summaries/` is left in place but no longer updated.

## Tests

```bash
bash tests/run.sh bash      # every suite against the Bash scripts, plus bash-vs-pwsh equivalence
bash tests/run.sh pwsh      # every suite against the PowerShell scripts
```

The tests use synthetic transcripts and a fake `claude`, so they spend no credit. They never
register a real scheduled task outside CI.
