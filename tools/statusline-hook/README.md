# statusline-hook

A Claude Code `StatusLine` hook that prints a colour-coded one-liner each turn:

```
model | ▓▓▓▓░░░░░░ 42% | 1h 1m 1s | $1.2345 | 5H: 35% (↺ 14:00) | 7D: 80% (↺ Mon 09:00)
```

`model | context bar | runtime | cost | 5-hour rate | 7-day rate`. Three equivalent
implementations — pick the one for your shell:

| File | Platform | Notes |
|------|----------|-------|
| `statusline-hook.ps1` | Windows (PowerShell) | Forces UTF-8 output. |
| `statusline-hook.sh` | Linux / macOS (Bash) | Requires `jq`. |
| `statusline-hook.py` | Cross-platform (Python stdlib) | UTF-8-safe stdin/stdout; run with `python3 statusline-hook.py`. Managed with `uv`. |

Each hook also appends the turn to `~/.claude/statusline/<project>/<session_id>.jsonl`
(`{session_id, ts, data}`). That export is **optional** — it's what powers the live
rate-limit panel in the [`usage-dashboard`](../../apps/usage-dashboard/) app. The dashboard
reads it if present and silently skips it if not.

## Quick start

Add the hook to `~/.claude/settings.json` (PowerShell shown; use `.sh`/`.py` analogously):

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File ~/.claude/statusline-hook.ps1"
  }
}
```

The base config dir defaults to `~/.claude`; set `$CLAUDE_DIR` (pathsep-separated) to override.
