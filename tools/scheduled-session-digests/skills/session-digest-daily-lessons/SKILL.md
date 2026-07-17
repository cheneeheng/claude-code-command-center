---
name: session-digest-daily-lessons
description: Run the daily-lessons scheduler from inside an interactive Claude Code session instead of via the cron/Task Scheduler trigger (which calls `claude --print` and burns programmatic credit). Use when the user asks to "run daily lessons", "extract today's lessons", or "do the daily lessons harvest". You act as coordinator: run the prepare script to stage one input file per new chat, fan the extraction out to subagents, advance the cursor, then git-sync the meta repo.
---

# Daily Lessons — interactive coordinator

You are the coordinator. The prepare script scans `~/.claude/projects` for new
chats and stages per-chat input files; you spawn one subagent per chat to extract
lessons, advance the cursor over the verified outputs, commit, and clean up. No
`claude --print` is used anywhere.

## Step 1 — Run the prepare script

`C4_CLAUDE_META_DIR` must be set in the environment (the scheduler's
`~/.claude/claude-scheduler.env` sets it; the prepare script also sources that
file). The prepare and git-sync scripts are installed at
`$C4_CLAUDE_META_DIR/.claude/scripts/`.

Run the script for the current OS and capture stdout:

- Windows (PowerShell tool):
  `& "$env:C4_CLAUDE_META_DIR\.claude\scripts\daily-digest-prepare.ps1" -Scheduler daily-lessons`
- macOS / Linux (Bash tool):
  `bash "$C4_CLAUDE_META_DIR/.claude/scripts/daily-digest-prepare.sh" daily-lessons`

Pass `--full-scan` / `-FullScan` only if the user explicitly asks to reprocess
all history.

The last lines of output are `MANIFEST=<path>` and `JOBS=<n>`.

## Step 2 — Read the manifest

Read the `MANIFEST` file. It is a JSON object:

```json
{ "scheduler": "daily-lessons",
  "cursor": "<cursor file path>",
  "cursorEpoch": <epoch to write to the cursor after a fully successful run>,
  "jobs": [ { "uuid": "...", "date": "YYYY-MM-DD", "title": "...", "project": "...",
              "mtime": <source chat mtime, Unix epoch>,
              "input": "<absolute input file path>",
              "output": "<absolute output file path>" } ] }
```

`jobs` is sorted oldest-first by source chat mtime.

If `JOBS=0`: when `cursorEpoch` is greater than 0, write it to the `cursor` file
(recent chats were deliberately skipped; this saves rescanning them). Then delete
the staging directory (the manifest's parent directory), report "No new chats to
process", and stop. Do not commit.

## Step 3 — Fan out to subagents

For each manifest entry, spawn a `general-purpose` subagent **on the `sonnet` model
with medium reasoning effort** (set the Agent `model` to `sonnet`; lessons extraction
benefits from deeper reasoning — this mirrors the cron trigger's `--effort medium`).
Run them in parallel in batches of up to 5 (multiple Agent calls in one message),
waiting for each batch before starting the next. Give every subagent this task,
substituting the entry's `input` and `output`:

> Read the file at `<input>`. It has a header (UUID, Date, Title, Project) and a
> `## Conversation` section containing a transcript with `[USER]` and
> `[ASSISTANT]` turn markers.
>
> Extract lessons learned from that transcript. A lesson is a correction, failed
> command, misunderstood requirement, wrong assumption, or sequencing mistake —
> something a future session should avoid repeating. Do NOT capture things that
> worked first time, routine tool use, or preference changes that weren't errors.
>
> Create the parent directory of `<output>` if needed, then write `<output>` with
> this exact structure:
>
> ```markdown
> # Lessons — <Date>
> **Session**: <UUID>
> **Title**: <Title>
> **Project**: <Project>
>
> ## YYYY-MM-DD — <short title naming the mistake, not the fix>
>
> **What happened:** one or two sentences — the concrete mistake.
>
> **Lesson:** one or two sentences — the actionable rule to apply next time.
> ```
>
> Repeat the `## …` block for each lesson. Use the chat's Date, prefer concrete
> file paths / command names, keep each entry under 6 sentences.
>
> If the transcript contains no meaningful lessons, instead write `<output>` with
> exactly:
>
> ```markdown
> # Lessons — <Date>
> **Session**: <UUID>
> **Title**: <Title>
> **Project**: <Project>
>
> _No lessons extracted from this session._
> ```
>
> Report one line: the output path and how many lessons you wrote.

Every chat must produce its output file (real lessons or the stub) — the stub is
what stops a chat being reprocessed next run.

## Step 4 — Advance the cursor

Walk the manifest's `jobs` in order and check each `output` file exists:

- If every output exists, write `cursorEpoch` (the integer, nothing else) to the
  `cursor` file.
- Otherwise, write the `mtime` of the last job before the first missing output
  (if the very first job's output is missing, leave the cursor untouched) and
  warn that the failed chats will be retried next run.

The cursor records the newest source chat that was fully handled, so a crashed
or failed job is picked up again by the next run.

## Step 5 — Commit

Run git-sync from the meta repo:

- Windows: `& "$env:C4_CLAUDE_META_DIR\.claude\scripts\git-sync.ps1" -Label "daily-lessons"`
- macOS / Linux: `bash "$C4_CLAUDE_META_DIR/.claude/scripts/git-sync.sh" "daily-lessons"`

git-sync is self-contained: run logs under `logs/` are gitignored (local-only), and if
the session is on a feature branch (e.g. one forced by a branch guard) git-sync merges
it into the default branch and deletes it, so the digest lands on main. Do not make any
extra commits.

## Step 6 — Clean up and report

Delete the staging directory
(`$C4_CLAUDE_META_DIR/.claude/scheduled-session-digests/daily-lessons/`) — the
staged inputs and manifest are no longer needed.

State how many chats were processed and whether the commit/push succeeded.
