# statusline-cost-dashboard

Terminal **statusline hook** plus a live **token/cost dashboard** for Claude Code sessions.

The statusline hook scripts live in the folder root; the dashboard server and its
scheduled-task scripts live in `cc-statusline-dashboard-server/`.

| File | Description |
|------|-------------|
| `statusline.ps1` / `statusline.sh` | Claude Code `StatusLine` hook (PowerShell / Bash). Reads the JSON piped by Claude Code each turn, prints a colour-coded one-liner (`model \| context bar \| runtime \| cost \| 5H rate \| 7D rate`), and appends a compact record to `~/.claude/statusline/<project>/<session>.jsonl`. The Bash version needs `jq`. |
| `statusline.py` | Abandoned Python port — has a stdin pipe bug; **do not use**. |
| `cc-statusline-dashboard-server/` | Stdlib-only HTTP server (default port 8080) that reads `~/.claude/projects/**/*.jsonl` (history) and `~/.claude/statusline/**/*.jsonl` (live rates) and serves a single-page dashboard: token charts, cost by model, rate-limit gauges, session table. See its own README for the data-flow walkthrough. |

## Quick start (Windows)

1. Add the `StatusLine` hook to `~/.claude/settings.json` pointing at `statusline.ps1`.
2. Run `cc-statusline-dashboard-server/cc-statusline-dashboard-server-setup.ps1` to start the
   server automatically, or run it directly with `uv`:
   ```bash
   uv run python cc-statusline-dashboard-server/cc-statusline-dashboard-server.py
   ```
3. Open <http://localhost:8080>.

No runtime dependencies — Python is stdlib-only and managed with `uv` (`pyproject.toml`).
