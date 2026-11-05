# What the store keeps

An export reads every transcript under `<claude dir>/projects/**/*.jsonl` and writes what it
finds into `usage.db`. This page lists every field it writes and where each one comes from, so you
know what the dashboard still has after Claude Code deletes a transcript.

The store keeps **counts and metadata, never conversation text**. The only text taken from a
prompt is the session title.

## Contents

- [Per session](#per-session)
  - [`sessions`: one row per session](#sessions-one-row-per-session)
  - [`messages`: one row per assistant reply](#messages-one-row-per-assistant-reply)
  - [`events`: one row per countable use](#events-one-row-per-countable-use)
- [Bookkeeping](#bookkeeping)
- [Not stored](#not-stored)

## Per session

A session is one parent transcript, `projects/<project>/<session uuid>.jsonl`. Subagent and
workflow transcripts, any `.jsonl` deeper under `projects/<project>/<session uuid>/`, are folded
into that session: their replies and uses count towards it, but they never set its title or cwd.

Each session gets one `sessions` row, plus one `messages` row per reply and one `events` row per
use. All timestamps are ISO-8601 strings in UTC, taken from the transcript line's `timestamp`. A
line without one is stored with a null `ts` and counts in no dashboard figure.

### `sessions`: one row per session

| Column | Source |
|---|---|
| `id` | The first 8 characters of the parent transcript's file name (the session uuid). |
| `project` | The folder under `projects/`: Claude Code's encoding of the working dir, such as `C--Users-me-repo`. |
| `title` | The last `custom-title` record (a `/rename`). Without one, the first line of the first typed prompt, cut to 80 characters. Tool results, meta records, interrupt markers and lines starting with `<` (slash-command records) are not prompts. |
| `cwd` | The last `cwd` field in the parent transcript. |
| `started` | The earliest `ts` of the session's stored replies. |
| `ended` | The latest `ts` of the session's stored replies. |

A re-export never clears `title` or `cwd`: a value only replaces the stored one when the new one
is not null.

### `messages`: one row per assistant reply

Only `assistant` lines carry token usage. A streamed reply spans several lines with the same
`message.id` and `requestId`, so the last line's usage is the one kept.

| Column | Source |
|---|---|
| `key` | `message.id` + `:` + `requestId`, else the line's `uuid`. The same reply copied into several files (a fork or a resume) is one row. |
| `session_id` | The session that first stored the reply. A later copy in another session never moves it. |
| `model` | `message.model`. Empty or `<synthetic>` is stored as `unknown`. |
| `ts` | The timestamp of the reply's last line. |
| `input` | `usage.input_tokens`: uncached input. |
| `output` | `usage.output_tokens`. |
| `cache_write` | `usage.cache_creation_input_tokens` minus the 1-hour writes: 5-minute cache writes. |
| `cache_read` | `usage.cache_read_input_tokens`. |
| `cache_write_1h` | `usage.cache_creation.ephemeral_1h_input_tokens`. |

A re-export replaces the counts only when the new copy has at least as many output tokens, because
a copy with fewer is a snapshot taken mid-stream. Cost is not stored: the dashboard works it out
from these counts and current prices.

### `events`: one row per countable use

| `kind` | Recorded when | `name` |
|---|---|---|
| `tool` | An assistant line has a `tool_use` block. | The tool name, such as `Bash` or `mcp__server__tool`. |
| `skill` | That tool is `Skill`. Also recorded as a `tool`. | The `skill` input, such as `plugin:skill`. |
| `agent` | That tool is `Agent` or `Task`. Also recorded as a `tool`. | The `subagent_type` input, else `general-purpose`. |
| `command` | A user line starts with `<command-`. | The slash command, without the `/`. |
| `interrupt` | A user line starts with `[Request interrupted by user`. | Empty. |
| `tool_error` | A user line has a `tool_result` with `is_error: true`. | The failed tool's name, or empty when its call is in another file. |

The other columns are `ts`, `session_id` (the session that first stored it) and `key`, which is
`<kind>:<id>`: the tool block `id` for tool uses and errors, the line `uuid` for commands and
interrupts. An event is written once and never updated.

## Bookkeeping

These tables are not per session. They let the next export skip work.

| Table | Holds |
|---|---|
| `files` | One row per transcript: `path`, `size`, `mtime_ns`, `exported_at`. An export re-parses a file only when its size or mtime differs. |
| `meta` | `last_export`: when the last export ran. |

The schema version is SQLite's `PRAGMA user_version`, not a row.

## Not stored

Once a transcript is deleted, these are gone, because the export never copies them:

- Prompt and reply text, apart from the title.
- Thinking, tool inputs and tool outputs, apart from the skill name and the subagent type.
- Attachments, images and file snapshots.
- Everything else on a line: git branch, Claude Code version, permission mode and so on.

Deleting a transcript also ends `claude --resume` for that session. Delete only sessions that have
ended and been exported since.
