---
name: session-digest-daily-lessons
description: Run the daily-lessons scheduler from inside an interactive Claude Code session instead of via the cron/Task Scheduler trigger (which calls `claude --print` and burns programmatic credit). Use when the user asks to "run daily lessons", "extract today's lessons", or "do the daily lessons harvest". You act as coordinator: run the prepare script to stage one input file per new chat, fan the extraction out to subagents, then git-sync the meta repo.
---

# Daily Lessons — interactive coordinator

You are the coordinator. The prepare script scans `~/.claude/projects` for new
chats and stages per-chat input files; you spawn one subagent per chat to extract
lessons; then you commit the results. No `claude --print` is used anywhere.

## Step 1 — Run the prepare script

`C4_CLAUDE_META_DIR` must be set in the environment (the scheduler's
`~/.claude/claude-scheduler.env` sets it; the prepare script also sources that
file). The prepare and git-sync scripts are installed at
`$C4_CLAUDE_META_DIR/.claude/scripts/`.

Run the script for the current OS and capture stdout:

- Windows (PowerShell tool):
  `& "$env:C4_CLAUDE_META_DIR\.claude\scripts\daily-lessons-prepare.ps1"`
- macOS / Linux (Bash tool):
  `bash "$C4_CLAUDE_META_DIR/.claude/scripts/daily-lessons-prepare.sh"`

Pass `--full-scan` / `-FullScan` only if the user explicitly asks to reprocess
all history.

The last lines of output are `MANIFEST=<path>` and `JOBS=<n>`.

## Step 2 — Check for work

If `JOBS=0`, report "No new chats to process" and stop. Do not commit.

## Step 3 — Read the manifest

Read the `MANIFEST` file. It is a JSON array; each entry is:

```json
{ "uuid": "...", "date": "YYYY-MM-DD", "title": "...", "project": "...",
  "input": "<absolute input file path>", "output": "<absolute output file path>" }
```

## Step 4 — Fan out to subagents

For each manifest entry, spawn a `general-purpose` subagent **on the `sonnet` model
with high reasoning effort** (set the Agent `model` to `sonnet`; lessons extraction
benefits from deeper reasoning). Run them in parallel in batches of up to 5 (multiple
Agent calls in one message), waiting for each batch before starting the next. Give
every subagent this task, substituting the entry's `input` and `output`:

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

## Step 5 — Commit

After all subagents finish, run git-sync from the meta repo:

- Windows: `& "$env:C4_CLAUDE_META_DIR\.claude\scripts\git-sync.ps1" -Label "daily-lessons"`
- macOS / Linux: `bash "$C4_CLAUDE_META_DIR/.claude/scripts/git-sync.sh" "daily-lessons"`

git-sync writes its own run log under `logs/` *after* it commits, so that log is left
uncommitted. Make one trailing commit to capture it (a plain commit creates no new log,
so it terminates): in `$C4_CLAUDE_META_DIR` run `git add -A`, and if anything is staged,
`git commit -m "daily-lessons: git-sync log"` then `git push` if a remote is configured.

## Step 6 — Report

State how many chats were processed and whether the commit/push succeeded.
