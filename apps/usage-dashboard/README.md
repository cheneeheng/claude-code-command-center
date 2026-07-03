# Claude Code Usage Dashboard

An HTTP server that reads Claude Code's local logs and serves a single-page,
interactive insight dashboard of token usage, cost, and live rate limits:
range/project scoping, plan ROI, week-over-week trend deltas, a 12-month
activity heatmap, model-mix / hour-of-week / tool profiles, daily token/cost
charts, per-project and per-model breakdowns, drill-down with shareable URLs,
per-session economics ($/hr, cache hit %), a live rate-limit trajectory with cap
ETA and reset countdowns, and Markdown / CSV report export. Its one dependency
is the local [`claude-usage`](../../libs/claude-usage/) library (transcript
parsing + pricing); run it with `uv run python usage-dashboard.py`.

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
| **Cost** | **Estimated** — token counts × the `claude-usage` pricing table (**canonical** in v4) | **Actual** — the real `total_cost_usd` Anthropic reported (informational only) |
| **History** | Full history | Only recent (sessions idle past the timeout are dropped) |

The sources overlap only on "cost", historically the source of confusion here.
The v4 rule is simple:

> **The pricing-table estimate is canonical** for every aggregate and every
> session row. There is no cost overlay. The statusline's actual per-session cost
> is shown only in the live rate-limit card (`live.sessions[].session_cost`),
> informational, never merged into `stats` or `sessions`.

The statusline's `total_cost_usd` was judged unreliable, so v4 removed the
former `merge.py._apply_actual_cost` overlay outright.

---

## Module layout

```
usage-dashboard.py                  ← entry point (CLI, starts HTTP server)
│
├── claude-usage (library)          ← transcript parsing + pricing (load_usage, estimated_cost)
├── backend/dashboard_config.py     ← CLAUDE_DIRS, live-session timeout, plan price
│
├── backend/session_stats.py    ─┐
├── backend/live_statusline.py  ─┤── the two data sources + the reconciler
├── backend/merge.py            ─┘
│
├── backend/dashboard_server.py     ← HTTP transport only
└── web/{dashboard.html, css/, js/} ← UI (renders the payload, computes nothing)
```

## Data flow — request to pixels

```
        ~/.claude/projects/**/*.jsonl            ~/.claude/statusline/**/*.jsonl
        (transcripts, written by Claude)         (written by statusline-hook.ps1 hook)
                  │                                          │
                  ▼                                          ▼
    ┌──────────────────────────────┐         ┌──────────────────────────────┐
    │  session_stats.py            │         │  live_statusline.py          │
    │  load_cached() (memoized)    │         │  read_statusline(timeout)    │
    │                              │         │                              │
    │  per-session tokens          │         │  live sessions only:         │
    │  + ESTIMATED cost (canonical)│         │   · 5h / 7d rate limits      │
    │    (tokens × pricing table)  │         │   · context-window %         │
    │                              │         │   · actual cost (info only)  │
    │  ALL sessions, full history  │         │   · model display name       │
    └──────────────┬───────────────┘         └───────────────┬──────────────┘
                   │                                          │
                   └────────────────────┬─────────────────────┘
                                        ▼
                        ┌─────────────────────────────────────────┐
                        │  merge.py                               │
                        │  build_payload(timeout, range, project) │
                        │                                         │
                        │  1. load_cached()  (memoized parse)     │
                        │  2. summarize_sessions(range, project)  │
                        │       scoped totals, deltas, plan,      │
                        │       breakdowns, activity series       │
                        │  3. strip internal `per_model`          │
                        └────────────────┬────────────────────────┘
                                         ▼
                            { stats, sessions, live }
                                         │
                                         ▼
                        ┌───────────────────────────────────┐
                        │  dashboard_server.py  (Handler)   │
                        │  GET /            → dashboard.html │
                        │  GET /dashboard.css|.js → assets   │
                        │  GET /api/data    → JSON payload   │
                        │  GET /api/live    → live block only│
                        │  GET /api/export.csv → session CSV │
                        │  GET /api/report.md → Markdown     │
                        └────────────────┬──────────────────┘
                                         │  HTTP (localhost:8080)
                                         ▼
                        ┌───────────────────────────────────┐
                        │  dashboard.js  (browser)          │
                        │  fetch /api/data → render()       │
                        │  draws charts, tables, gauges     │
                        │  computes NOTHING — pure display  │
                        │  60s full refresh · 10s live poll │
                        └───────────────────────────────────┘
```

One sentence: **two log sources go in, `merge.py` aggregates the transcript
estimates (scoped to the requested range/project) and attaches the live block,
the server ships it as JSON, and the `js/` browser code just draws it.**

---

## Layout

```
usage-dashboard.py     entry point (CLI, starts the server)
backend/               Python: config + the two sources + reconciler + HTTP handler
web/                   the UI: dashboard.html + split css/ and js/
scripts/               Windows Task Scheduler install + launch helpers
```

## Module responsibilities

| File | Responsibility |
|------|----------------|
| `usage-dashboard.py` | Entry point. CLI args (`--host/--port/--claude-dir`), trims statusline logs on startup, starts the HTTP server. |
| `backend/dashboard_config.py` | Runtime config only: `CLAUDE_DIRS` (overridable via `--claude-dir`), the live-session timeout, and the monthly `PLAN_PRICE_USD`. Parsing and the pricing table live in the `claude-usage` library. |
| `backend/session_stats.py` | **Source 1.** Loads sessions + the `Activity` rollup from `claude-usage` (via a memoized parse cache), scopes them to the request's `range`/`project`, and aggregates them (`summarize_sessions`) into totals, trend deltas, plan value, top sessions, the by-day / by-project / by-model / model-mix / hour-of-week / tools breakdowns, cache savings, month-to-date cost + projection, and the 364-day `heatmap`. Adds per-session derived economics (duration, $/hr, cache hit %). |
| `backend/live_statusline.py` | **Source 2.** Reads the statusline logs into live per-session state (rate limits, context %, informational actual cost), plus rate-limit `history` and a cap-ETA `forecast`; also `trim_statusline_logs` to bound disk growth. |
| `backend/merge.py` | Assembles the `/api/data` payload from the memoized parse + live block. No cost overlay — the estimate is canonical. |
| `backend/report.py` | Renders the `/api/report.md` Markdown usage report from a built payload (formatting only, no new aggregation). |
| `backend/dashboard_server.py` | HTTP transport only: serves the static assets, `/api/data` (`range`/`project` scoped), the cheap `/api/live` fast-poll block, the `/api/export.csv` download, and the `/api/report.md` report. |
| `web/dashboard.html` + `web/css/` + `web/js/` | The UI. The `js/` scripts render the payload, draw the charts, and handle the client-side controls (refresh, theme, pagination, session timeout); `css/` holds the styles. Both are split into small single-concern files and concatenated by `dashboard_server.py` into one `/dashboard.css` and one `/dashboard.js` response. |
| `scripts/*.ps1` | Windows Task Scheduler helpers: `usage-dashboard-setup.ps1` (install/uninstall the logon + resume task) and `usage-dashboard-start-once.ps1` (the task action; launches the server only if the port is free). |

---

## Cost: the estimate is canonical

Every cost figure on the dashboard — `total_cost_usd`, the daily-cost chart, the
by-model and by-project breakdowns, and every session row — is the **estimate**:

- **Estimated** (`claude_usage.estimated_cost`): `tokens / 1e6 × per-token price`,
  summed across the four token classes (input, output, cache-write, cache-read)
  and every model a session used. Prices come from `claude_usage.MODEL_COSTS`,
  keyed by model *family* so `claude-opus-4-7` and `claude-opus-4-8` share a row.
  Update that table when Anthropic changes pricing.
- **Actual** (`live_statusline`): read straight from `data.cost.total_cost_usd`
  in the statusline log. v4 judged this figure unreliable, so it is **no longer
  merged into any aggregate**. It survives only as the informational `Cost`
  column in the live rate-limit card, for the sessions active right now.

There is intentionally no estimated-vs-actual reconciliation left in the code.

---

## Running it

```bash
# Default: localhost:8080, reads ~/.claude
uv run python usage-dashboard.py

# Custom host/port
uv run python usage-dashboard.py --host 0.0.0.0 --port 9000

# Aggregate multiple Claude config dirs as if they were one
uv run python usage-dashboard.py --claude-dir ~/.claude ~/.claude_devcontainer
```

To run it automatically on Windows (logon + resume from sleep), use the
scheduled-task installer:

```powershell
.\scripts\usage-dashboard-setup.ps1              # install
.\scripts\usage-dashboard-setup.ps1 -Action uninstall
```

### Environment variables

| Variable | Default | Effect |
|----------|---------|--------|
| `C4_CLAUDE_DIR` | `~/.claude` | One or more config dirs (`os.pathsep`-separated). Overridden by `--claude-dir`. |
| `C4_STATUSLINE_LIVE_TIMEOUT` | `1800` | Seconds a session may be idle before it drops out of the live view. Also adjustable per-request via the dashboard's "session timeout" control. |
| `C4_PLAN_PRICE_USD` | *(unset)* | Your monthly Claude subscription price. Set it to light up the **Plan Value** card (month-to-date usage value ÷ plan price). Unset → the card shows a setup hint. |

### Endpoints

| Method / Path | Description |
|---|---|
| `GET /`, `/dashboard.css`, `/dashboard.js` | Static shell + concatenated CSS/JS bundles. |
| `GET /api/data?range=&project=&live_timeout=` | Full `{stats, sessions, live}` payload. `range` ∈ `7d,30d,90d,12m,all` (default `all`); `project` is an exact-match filter. |
| `GET /api/live?live_timeout=` | The `live` block only (statusline read, no transcript parse) — the 10s fast-poll endpoint. |
| `GET /api/export.csv?range=&project=` | Range/project-scoped per-session CSV download. |
| `GET /api/report.md?range=&project=` | Range/project-scoped Markdown usage report download. |

---

## Extending it

- **New model / new pricing:** edit `claude_usage.MODEL_COSTS` (in the `claude-usage`
  library). If the family detection in `claude_usage.model_family` doesn't catch the id,
  adjust it there. The UI's
  matching color/label logic lives in `js/models.js` (`modelFamily`, `MODEL_SHADES`,
  `modelShort`) and must be kept in step.
- **New aggregate stat:** add it in `session_stats.summarize_sessions`, then render
  it in `js/render.js`. Keep all computation server-side.
- **New live field:** surface it in `live_statusline._live_session`, then render it.

The payload contract (`{stats, sessions, live}` and their keys) is what couples
the server to the `js/` render code — change both ends together.
