---
name: session-digest-daily-summary
description: Run the daily-summary scheduler from inside an interactive Claude Code session instead of via the cron/Task Scheduler trigger (which calls `claude --print` and burns programmatic credit). Use when the user asks to "run daily summary", "summarise today's chats", or "do the daily summary". You act as coordinator: run the prepare script to stage one input file per new chat, fan the summarisation out to subagents, then git-sync the meta repo.
---

# Daily Summary — interactive coordinator

You are the coordinator. The prepare script scans `~/.claude/projects` for new
chats and stages per-chat input files; you spawn one subagent per chat to write a
summary; then you commit the results. No `claude --print` is used anywhere.

## Step 1 — Run the prepare script

`CLAUDE_META_DIR` must be set in the environment (the scheduler's
`~/.claude/claude-scheduler.env` sets it; the prepare script also sources that
file). The prepare and git-sync scripts are installed at
`$CLAUDE_META_DIR/.claude/scripts/`.

Run the script for the current OS and capture stdout:

- Windows (PowerShell tool):
  `& "$env:CLAUDE_META_DIR\.claude\scripts\daily-summary-prepare.ps1"`
- macOS / Linux (Bash tool):
  `bash "$CLAUDE_META_DIR/.claude/scripts/daily-summary-prepare.sh"`

Pass `--full-scan` / `-FullScan` only if the user explicitly asks to reprocess
all history.

The last lines of output are `MANIFEST=<path>` and `JOBS=<n>`.

## Step 2 — Check for work

If `JOBS=0`, report "No new chats to summarise" and stop. Do not commit.

## Step 3 — Read the manifest

Read the `MANIFEST` file. It is a JSON array; each entry is:

```json
{ "uuid": "...", "date": "YYYY-MM-DD", "title": "...", "project": "...",
  "input": "<absolute input file path>", "output": "<absolute output file path>" }
```

## Step 4 — Fan out to subagents

For each manifest entry, spawn a `general-purpose` subagent **on the `haiku` model**
(set the Agent `model` to `haiku` — summarisation is cheap and high-frequency). Run
them in parallel in batches of up to 5 (multiple Agent calls in one message), waiting
for each batch before starting the next. Give every subagent this task, substituting
the entry's `input` and `output`:

> Read the file at `<input>`. It has a header (UUID, Date, Title, Project) and a
> `## Conversation` section containing a transcript with `[USER]` and
> `[ASSISTANT]` turn markers.
>
> Create the parent directory of `<output>` if needed, then write a concise
> summary to `<output>` using this structure (skip any section that does not
> apply, keep the whole file under 80 lines, be concrete — name files, functions,
> commands):
>
> ```markdown
> # Chat Summary — <Date>
> **Session**: <UUID>
> **Title**: <Title>
> **Project**: <Project>
>
> ## What was worked on
> ## Decisions made
> ## Outcomes
> ## Current State
> ## Pending / Next Steps
> ## Key Facts for Next Session
> ## Open items
> ```
>
> If the conversation is very short or has no meaningful work, instead write a
> single `## Note` section: `No significant work recorded.`
>
> Report one line: the output path you wrote.

Every chat must produce its output file — that is what stops a chat being
reprocessed next run.

## Step 5 — Commit

After all subagents finish, run git-sync from the meta repo:

- Windows: `& "$env:CLAUDE_META_DIR\.claude\scripts\git-sync.ps1" -Label "daily-summary"`
- macOS / Linux: `bash "$CLAUDE_META_DIR/.claude/scripts/git-sync.sh" "daily-summary"`

git-sync writes its own run log under `logs/` *after* it commits, so that log is left
uncommitted. Make one trailing commit to capture it (a plain commit creates no new log,
so it terminates): in `$CLAUDE_META_DIR` run `git add -A`, and if anything is staged,
`git commit -m "daily-summary: git-sync log"` then `git push` if a remote is configured.

## Step 6 — Report

State how many chats were summarised and whether the commit/push succeeded.
