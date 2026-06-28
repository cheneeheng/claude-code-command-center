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
| `Session` | Dataclass: tokens (input/output/cache), `total_tokens`, estimated `cost_usd`, `models`, `project`, timestamps. |
| `claude_dirs()` | Resolve the Claude config dirs (honours pathsep-separated `$C4_CLAUDE_DIR`). |
| `transcript_files(dirs=None)` | The raw transcript paths, deduped and sorted. |
| `estimated_cost(per_model)` | USD estimate from per-model token counts and `MODEL_COSTS`. |
| `model_family` / `model_costs` / `MODEL_COSTS` | Pricing table and family collapsing. |

**Cost is estimated** (token counts × list price), not the amount Anthropic billed.

Stdlib only (`dependencies = []`), strict-typed, managed with `uv`.
