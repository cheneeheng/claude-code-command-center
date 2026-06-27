# Claude Code Usage Dashboard

An HTTP server that reads Claude Code's local logs and serves a single-page
dashboard of token usage, cost, and live rate limits. Its one dependency is the
local [`claude-usage`](../../libs/claude-usage/) library (transcript parsing +
pricing); run it with `uv run python cc-statusline-dashboard-server.py`.

```
http://localhost:8080
```

Historical usage/cost comes from Claude Code's own `~/.claude/projects/**/*.jsonl`
transcripts. The **live rate-limit panel** is powered by the optional
[`statusline-hook`](../../tools/statusline-hook/) tool, which exports
`~/.claude/statusline/<project>/<session>.jsonl`. The dashboard reads that export if present
and silently skips it (showing "Hook not set up") if not.

---

## The one thing to understand: two data sources

Every number on the dashboard comes from one of **two independent sources**.
Keeping them straight is the whole point of the module layout.

| | Source 1 — Session transcripts | Source 2 — Statusline logs |
|---|---|---|
| **Files** | `~/.claude/projects/**/*.jsonl` | `~/.claude/statusline/<project>/<session>.jsonl` |
| **Written by** | Claude Code itself, every turn | The `statusline-hook.ps1` / `.sh` hook, every prompt |
| **Module** | `session_stats.py` | `live_statusline.py` |
| **Gives us** | Exact token counts per session (input / output / cache) for **all** sessions, ever | Live state for **currently active** sessions: rate limits (5h / 7d), context-window %, and the model display name |
| **Cost** | **Estimated** — token counts × the `claude-usage` pricing table | **Actual** — the real `total_cost_usd` Anthropic reported |
| **History** | Full history | Only recent (sessions idle past the timeout are dropped) |

These two notions of "cost" are the only place the sources overlap, and it is
the historical source of confusion in this code. The rule is simple:

> **Actual cost wins when it's available.** For a session that is currently
> live, `merge.py` overlays the statusline's actual cost on top of the token
> estimate. Every other (historical) session keeps its estimate.

That single override lives in `merge.py._apply_actual_cost` and nowhere else.

---

## Module layout

```
cc-statusline-dashboard-server.py   ← entry point (CLI, starts HTTP server)
│
├── claude-usage (library)          ← transcript parsing + pricing (load_sessions, estimated_cost)
├── dashboard_config.py             ← CLAUDE_DIRS, live-session timeout
│
├── session_stats.py    ─┐
├── live_statusline.py  ─┤── the two data sources + the reconciler
├── merge.py            ─┘
│
├── dashboard_server.py             ← HTTP transport only
└── dashboard.{html,css,js}         ← UI (renders the payload, computes nothing)
```

## Data flow — request to pixels

```
        ~/.claude/projects/**/*.jsonl            ~/.claude/statusline/**/*.jsonl
        (transcripts, written by Claude)         (written by statusline-hook.ps1 hook)
                  │                                          │
                  ▼                                          ▼
    ┌──────────────────────────────┐         ┌──────────────────────────────┐
    │  session_stats.py            │         │  live_statusline.py          │
    │  load_sessions()             │         │  read_statusline(timeout)    │
    │                              │         │                              │
    │  per-session tokens          │         │  live sessions only:         │
    │  + ESTIMATED cost            │         │   · 5h / 7d rate limits      │
    │    (tokens × pricing table)  │         │   · context-window %         │
    │                              │         │   · ACTUAL cost (from API)   │
    │  ALL sessions, full history  │         │   · model display name       │
    └──────────────┬───────────────┘         └───────────────┬──────────────┘
                   │                                          │
                   └────────────────────┬─────────────────────┘
                                        ▼
                        ┌───────────────────────────────────┐
                        │  merge.py                         │
                        │  build_payload(live_timeout)      │
                        │                                   │
                        │  1. _apply_actual_cost()          │
                        │     live session?  → actual cost  │   ← the ONLY
                        │     historical?    → keep estimate│     overlap
                        │  2. summarize_sessions()          │
                        │       totals, by_day/project/model│
                        │  3. strip internal `per_model`    │
                        └────────────────┬──────────────────┘
                                         ▼
                            { stats, sessions, live }
                                         │
                                         ▼
                        ┌───────────────────────────────────┐
                        │  dashboard_server.py  (Handler)   │
                        │  GET /            → dashboard.html │
                        │  GET /dashboard.css|.js → assets   │
                        │  GET /api/data    → JSON payload   │
                        └────────────────┬──────────────────┘
                                         │  HTTP (localhost:8080)
                                         ▼
                        ┌───────────────────────────────────┐
                        │  dashboard.js  (browser)          │
                        │  fetch /api/data → render()       │
                        │  draws charts, tables, gauges     │
                        │  computes NOTHING — pure display  │
                        │  refresh loop every 60s           │
                        └───────────────────────────────────┘
```

One sentence: **two log sources go in, `merge.py` overlays real cost on live
sessions and aggregates everything, the server ships it as JSON, and
`dashboard.js` just draws it.**

---

## Module responsibilities

| File | Responsibility |
|------|----------------|
| `cc-statusline-dashboard-server.py` | Entry point. CLI args (`--host/--port/--claude-dir`), trims statusline logs on startup, starts the HTTP server. |
| `dashboard_config.py` | Runtime config only: `CLAUDE_DIRS` (overridable via `--claude-dir`) and the live-session timeout. Parsing and the pricing table live in the `claude-usage` library. |
| `session_stats.py` | **Source 1.** Loads per-session token/cost summaries from `claude-usage` and aggregates them (`summarize_sessions`) into totals and the by-day / by-project / by-model breakdowns. |
| `live_statusline.py` | **Source 2.** Reads the statusline logs into live per-session state (rate limits, context %, *actual* cost); also `trim_statusline_logs` to bound disk growth. |
| `merge.py` | Reconciles the two sources into the `/api/data` payload. Owns the estimated-vs-actual cost override. |
| `dashboard_server.py` | HTTP transport only: serves the static assets and the `merge.build_payload` JSON. |
| `dashboard.html` / `.css` / `.js` | The UI. `dashboard.js` renders the payload, draws the charts, and handles the client-side controls (refresh, theme, pagination, session timeout). |

---

## Cost: estimated vs actual, in detail

```
   per session:
                       is it live RIGHT NOW (in statusline, within timeout)?
                                  │
                   ┌──────────────┴──────────────┐
                  YES                            NO
                   │                              │
        use ACTUAL cost from              use ESTIMATED cost
        statusline (real $ billed)        (tokens × pricing table)
                   │                              │
                   └──────────────┬───────────────┘
                                  ▼
                    feeds total_cost_usd, daily-cost chart, session rows
                    (cost-by-model breakdown stays estimate — statusline
                     doesn't split cost per model)
```

- **Estimated** (`claude_usage.estimated_cost`): `tokens / 1e6 × per-token price`,
  summed across the four token classes (input, output, cache-write, cache-read)
  and every model a session used. Prices come from `claude_usage.MODEL_COSTS`,
  keyed by model *family* so `claude-opus-4-7` and `claude-opus-4-8` share a row.
  Update that table when Anthropic changes pricing.
- **Actual** (`live_statusline`): read straight from `data.cost.total_cost_usd`
  in the statusline log — the figure Claude Code displayed.
- **What the UI shows:** `total_cost_usd`, the daily-cost chart, and a live
  session's row reflect actual cost wherever a live session was matched;
  everything else is the estimate. The **cost-by-model** breakdown is always the
  estimate (the statusline doesn't attribute cost per model).

If estimated and actual diverge, the pricing table is stale — not a bug in the
parsing.

---

## Running it

```bash
# Default: localhost:8080, reads ~/.claude
uv run python cc-statusline-dashboard-server.py

# Custom host/port
uv run python cc-statusline-dashboard-server.py --host 0.0.0.0 --port 9000

# Aggregate multiple Claude config dirs as if they were one
uv run python cc-statusline-dashboard-server.py --claude-dir ~/.claude ~/.claude_devcontainer
```

To run it automatically on Windows (logon + resume from sleep), use the
scheduled-task installer:

```powershell
.\cc-statusline-dashboard-server-setup.ps1              # install
.\cc-statusline-dashboard-server-setup.ps1 -Action uninstall
```

### Environment variables

| Variable | Default | Effect |
|----------|---------|--------|
| `CLAUDE_DIR` | `~/.claude` | One or more config dirs (`os.pathsep`-separated). Overridden by `--claude-dir`. |
| `STATUSLINE_LIVE_TIMEOUT` | `1800` | Seconds a session may be idle before it drops out of the live view. Also adjustable per-request via the dashboard's "session timeout" control. |

---

## Extending it

- **New model / new pricing:** edit `claude_usage.MODEL_COSTS` (in the `claude-usage`
  library). If the family detection in `claude_usage.model_family` doesn't catch the id,
  adjust it there. The UI's
  matching color/label logic lives in `dashboard.js` (`modelFamily`, `MODEL_SHADES`,
  `modelShort`) and must be kept in step.
- **New aggregate stat:** add it in `session_stats.summarize_sessions`, then render
  it in `dashboard.js`. Keep all computation server-side.
- **New live field:** surface it in `live_statusline._live_session`, then render it.

The payload contract (`{stats, sessions, live}` and their keys) is what couples
the server to `dashboard.js` — change both ends together.
