# usage-insights

A local dashboard over your Claude Code usage that helps you decide what to change. One page
answers three questions:

- **What will I spend?** Tokens and cost so far this week and month, the forecast with a low/high
  band, a 30-day pace strip, and the month forecast per project.
- **Where does it go?** Projects ranked by cost with their change against the previous period,
  models ranked by cost, and the top sessions.
- **What should I fix?** Every skill and subagent with a health status, tool calls ranked by count,
  and the built-in tools and MCP servers you never call.

It replaces [`usage-dashboard`](../usage-dashboard/). Data comes from Claude Code's transcripts
(`~/.claude/projects/**/*.jsonl`), copied into a local store, so your history outlives Claude
Code's transcript cleanup.

## Install

Install from this checkout. You need [`uv`](https://docs.astral.sh/uv/) and
[`bun`](https://bun.sh/) on PATH. Each script builds the web frontend and installs the
`usage-insights` command with `uv tool install --editable`.

**Windows** (PowerShell):

```powershell
./scripts/usage-insights-setup.ps1 -Action install
```

This also registers the Task Scheduler task `\ClaudeAutomation\usage-insights\export`, which
copies new transcripts into the store daily at 12:00 and at logon, with no console window. You can
also install it through [`setup/command-center.ps1`](../../setup/) as the member
`usage-insights`.

**macOS and Linux** (bash):

```bash
bash scripts/usage-insights-setup.sh install
```

The script prints a crontab line for a daily export and does not edit your crontab. Add it with
`crontab -e`:

```
0 12 * * * <uv tool bin dir>/usage-insights export
```

The dashboard also exports on every launch and every refresh, on every OS, so the scheduled export
only matters for keeping history when you don't open the dashboard for a while.

**Uninstall:** `-Action uninstall` (Windows) or `uninstall` (bash) removes the task and the command.
The store is kept, and the script prints its path.

## Use

```
usage-insights                   # export, then serve http://127.0.0.1:8090/ and open the browser
usage-insights export            # export only
```

| Option | Default | Meaning |
|--------|---------|---------|
| `--port` | `8090` | Port to serve on. If a running `usage-insights` already holds it, the command opens the browser on it and exits. |
| `--host` | `127.0.0.1` | Address to bind. |
| `--claude-dir DIR` | `$C4_CLAUDE_DIR` or `~/.claude` | Claude config dir to read. Repeat it for several. |
| `--no-open` | off | Don't open the browser. |

Press Ctrl+C to stop the server. The range buttons (7d, 30d, 90d, all) scope the spend and health
counts. The forecast always covers the current week (Monday to Sunday) and calendar month.

## The store

The store is a SQLite file at `~/.usage-insights/usage.db`, or `$C4_USAGE_INSIGHTS_HOME/usage.db`.

- **Retention:** rows are never deleted. When Claude Code removes an old transcript, the sessions,
  messages, and events already exported stay in the store.
- **Incremental:** an export re-reads only transcripts whose size or modification time changed.
- **Cost** is computed when the page loads, from the price table in `claude-usage`, so a price fix
  needs no re-export. Models missing from the table are listed as unpriced instead of costed at $0.
- **Upgrades:** when a new version changes the store's schema, the next export copies the old file
  to `usage.db.bak` and rebuilds from the transcripts still on disk. Rows for transcripts Claude
  Code already deleted are lost in that rebuild, and the export prints a warning.

## Health statuses

Each skill and subagent gets the first status that matches, judged over all history in the store:

| Status | Meaning |
|--------|---------|
| `never_used` | Installed, never used. |
| `troubled` | At least 3 uses in the last 30 days, and at least 20% of them were followed by you interrupting Claude in the same session within 15 minutes. |
| `declining` | Uses in the last 30 days are below half of the 30 days before, and the earlier window had at least 4. |
| `unused_lately` | Last used more than 30 days ago. |
| `healthy` | Everything else. |

The **Invoked** column says whether Claude chose the skill (`auto`), you typed it as a slash
command (`typed`), or both. Names that are used but not installed (built-in skills, removed
plugins) show with source `unknown`. Installed but disabled plugins count as installed, so their
unused skills show as `never_used`.

## Develop

```
uv sync
uv run pytest                    # exporter, aggregation, and a booted server
uv run ruff check . && uv run mypy src
cd web && bun install && bun run dev   # Vite on :5173, proxying /api to 127.0.0.1:8090
cd web && bun run typecheck && bun run test && bun run build
```

`bun run build` writes the frontend into `src/usage_insights/static/`, which the server serves.
The design and its reasons are in [`product/ARCHITECTURE.md`](product/ARCHITECTURE.md) and the
build plan in [`product/plans/usage-insights.md`](product/plans/usage-insights.md).
