# claude-usage

A small, dependency-free library for reading **Claude Code's local session data**.

It models one well-defined external contract — the `~/.claude/projects/**/*.jsonl`
transcript layout that Claude Code writes — and turns it into per-session token/cost
summaries. It exists because more than one member needs this exact parsing: the
[`usage-dashboard`](../../apps/usage-dashboard/) app and the
[`usage-report`](../../tools/usage-report/) CLI both consume it.

## API

```python
from claude_usage import load_sessions, claude_dirs, estimated_cost, Session

for s in load_sessions():          # newest first; honours $C4_CLAUDE_DIR
    print(s.project, s.total_tokens, f"${s.cost_usd:.2f}")
```

| Symbol | Purpose |
|--------|---------|
| `load_sessions(dirs=None)` | Parse all transcripts into a list of `Session` (newest first). |
| `load_usage(dirs=None)` | Single parse pass returning `(sessions, Activity)` — the sessions above plus per-message rollups. |
| `parse_file(path)` | Parse one transcript into a `FileParse`: its `MessageUsage` replies and `UsageEvent` uses, deduped within the file. `load_usage` merges these globally. |
| `Session` | Dataclass: tokens (input/output/cache), `total_tokens`, estimated `cost_usd`, `models`, `project`, timestamps. |
| `MessageUsage` / `UsageEvent` / `FileParse` | One deduped reply, one counted use (a tool call), and one parsed file. |
| `Activity` | Dataclass: `daily` (364 `DayBucket`s, local time), `hour_dow` (7×24 token matrix, Mon..Sun), `tools` (tool_use counts by name). |
| `DayBucket` | Dataclass: one local day's `date`, `tokens`, estimated `cost`, distinct `sessions`, `per_family` tokens. |
| `claude_dirs()` | Resolve the Claude config dirs (honours pathsep-separated `$C4_CLAUDE_DIR`). |
| `transcript_files(dirs=None)` | The raw transcript paths, deduped and sorted. |
| `estimated_cost(per_model)` | USD estimate from per-model token counts, priced through `price_for`. |
| `price_for(model)` / `ModelPrice` / `MODEL_PRICES` | Per-version prices (longest model-id prefix wins), falling back to the family table. `None` means unpriced. |
| `model_family` / `model_costs` / `MODEL_COSTS` | Family collapsing and the family fallback table. |

**Cost is estimated** (token counts × list price), not the amount Anthropic billed. Cache writes
are split by TTL (`cache_write` for 5 minutes, `cache_write_1h` for 1 hour, priced at 2x input).

**Counting rules.** A streamed reply spans several lines sharing `message.id` + `requestId`. It
counts once, with the last line's usage, even when a resumed session copies it into another file.
Every `tool_use` block counts once by its `id`. Subagent and workflow transcripts under
`projects/<project>/<session-uuid>/` fold into their parent session.

Stdlib only (`dependencies = []`), strict-typed, managed with `uv`.
