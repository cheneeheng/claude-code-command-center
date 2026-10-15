# usage-insights — Architecture

A local dashboard that answers "what will I spend?", "where does it go?", and "what should I fix?"
over Claude Code usage. An exporter copies transcripts into an upsert-only SQLite store, an
aggregator turns the store plus an inventory of installed skills, agents, and MCP servers into one
JSON payload, and a React page renders that payload through a data-driven layout. Parsing and
pricing live in the in-repo `claude-usage` library, and plugin reading in `claude-plugins`.

## System context

```mermaid
flowchart LR
    cc["Claude Code"] -->|"~/.claude/projects/**/*.jsonl"| app((usage-insights))
    cfg["plugins, skills, agents,<br/>MCP config"] --> app
    app <-->|"usage.db"| db[("~/.usage-insights<br/>or $C4_USAGE_INSIGHTS_HOME")]
    you([You]) -->|"usage-insights → browser @ 127.0.0.1:8090"| app
    task["Task Scheduler (Windows)<br/>or cron (printed)"] -->|"usage-insights-bg export"| app
```

## Components

```mermaid
flowchart LR
  T["transcripts"] --> CU["libs/claude-usage<br/>parse_file, dedup, price, events"]
  CU --> EX["export.py<br/>incremental upsert"]
  EX --> DB[("usage.db")]
  P["plugins, skills, agents,<br/>MCP config"] --> CP["libs/claude-plugins"]
  CP --> INV["inventory.py"]
  P --> INV
  DB --> AG["aggregate.py<br/>projection, spend, health"]
  INV --> AG
  AG --> SV["server.py<br/>GET /api/summary, POST /api/refresh"]
  SV --> UI["web/ React app<br/>catalogue + defaultLayout"]
  CLI["cli.py"] --> SV
  CLI --> EX
```

| Module | Owns |
|--------|------|
| `cli.py` | `usage-insights` (export, then serve and open the browser) and `usage-insights export`; the bind-failure handling. |
| `store.py` | Schema, `PRAGMA user_version`, the backup before a rebuild, `BEGIN IMMEDIATE` and `ExportBusy`. |
| `export.py` | Skip unchanged files by size and mtime, upsert sessions, messages, and events. |
| `inventory.py` | Installed skills and agents (user, plugin, project), MCP servers, built-in lists. |
| `aggregate.py` | The `/api/summary` payload. Every tunable number is a constant at its top. |
| `server.py` | Host check, `/api/health`, `/api/summary`, `/api/refresh`, static files. |
| `web/src/catalogue/` | Presentational components with exported props types and no fetching. |
| `web/src/layout/defaultLayout.ts` | Sections as data: `{ id, title, question, panels: { component, select }[] }`. |

## Key flow — refresh

```mermaid
sequenceDiagram
    participant B as Browser
    participant S as server.py
    participant E as export.py
    participant D as usage.db
    participant A as aggregate.py

    B->>S: POST /api/refresh
    S->>E: run_export
    E->>D: BEGIN IMMEDIATE (timeout 5 s)
    alt another export holds the lock
        D-->>E: database is locked
        E-->>S: ExportBusy
        S-->>B: 409 export already running
    else
        E->>D: upsert changed files, set last_export
        S-->>B: 200 counts
        B->>S: GET /api/summary?range=30d
        S->>A: build summary (read-only connection)
        A->>D: query messages, events, sessions
        S-->>B: JSON payload
    end
```

## Key Decisions

### 2026-10-14 — Own an upsert-only store instead of reading transcripts live

**Status:** Accepted
**Context:** Claude Code deletes old transcripts, and re-parsing 979 MB of them takes about 9 s.
**Decision:** `usage-insights export` copies transcripts into SQLite, re-parsing only files whose
size or mtime changed, and only ever upserts rows. A schema version change backs the file up to
`usage.db.bak` and rebuilds from the transcripts still on disk.
**Consequences:** History outlives Claude Code's cleanup, and a repeat export takes well under 1 s.
A schema change loses rows for deleted transcripts, so additive changes are preferred. A copy of a
reply with fewer output tokens never replaces the stored one (added 2026-10-15), because a fork's
mid-stream snapshot, re-parsed later, used to shrink the finished reply.

### 2026-10-14 — Cost is computed at query time

**Status:** Accepted
**Context:** Prices change, and the price table had errors before this app existed.
**Decision:** The store keeps token counts only. `aggregate.py` prices them with
`claude_usage.price_for` on every request. Unknown models are reported as unpriced, never $0.
**Consequences:** A price fix needs no re-export.

### 2026-10-14 — One writer, and a second export gives up instead of waiting

**Status:** Accepted
**Context:** A first export of large history can take minutes, and the scheduled task, the CLI, and
the refresh button can all start one.
**Decision:** WAL mode, one `BEGIN IMMEDIATE` per export with a 5 s timeout, and `ExportBusy` on a
locked store: the CLI prints "export already running" and exits 0, and `/api/refresh` returns 409.
**Consequences:** The server keeps reading during an export. A refresh during a long export reports
busy instead of hanging.

### 2026-10-14 — Scheduled export, server on demand

**Status:** Accepted
**Context:** `usage-dashboard` kept a server running from logon. Here, the store only has to stay
current.
**Decision:** The Windows setup registers `\ClaudeAutomation\usage-insights\export`, running
`usage-insights-bg.exe export` (a GUI-script entry point, so no console window) daily at 12:00
and at logon. macOS and Linux get a printed cron line. The `usage-insights` command exports, then
serves until Ctrl+C.
**Consequences:** No background server and no port held between uses.

### 2026-10-14 — Stdlib HTTP server bound to localhost, with a Host check

**Status:** Accepted
**Context:** One local user and two JSON endpoints, and the payload holds session titles taken from
prompts.
**Decision:** `http.server.ThreadingHTTPServer`, bound to 127.0.0.1, rejecting any `Host` that is
not `127.0.0.1:<port>` or `localhost:<port>` with 403, against DNS rebinding.
`allow_reuse_address = False`, because on Windows `SO_REUSEADDR` lets a second bind onto a busy
port succeed.
**Consequences:** No web framework dependency. The Vite dev proxy must set `changeOrigin`.

### 2026-10-15 — Same-origin refresh, and a read-only server

**Status:** Accepted
**Context:** The review found that any web page could fire a no-cors `POST /api/refresh` (the
Host check passes, since the browser sends `Host: 127.0.0.1:<port>`), and that the server opened
the store read-write.
**Decision:** A POST must be same-origin: `Sec-Fetch-Site` decides when the browser sends it
(only `same-origin` and `none` pass), else an `Origin`, when present, must be the server's own
host. `Origin` alone is not enough, because the Vite dev proxy forwards the dev server's
`Origin`. The server reads the store through `store.connect_read_only` (`mode=ro`).
**Consequences:** Only the page itself, or a tool with no `Origin` such as `curl`, can start an
export. A server bug cannot write to the store.

### 2026-10-14 — The page layout is data, ready for AG-UI

**Status:** Accepted
**Context:** A later phase lets an AG-UI agent rearrange the dashboard.
**Decision:** Every panel is a catalogue component with a typed props contract and no data fetching.
`defaultLayout.ts` lists sections and panels as data, each panel with a `select` from the payload to
its props, and `App.tsx` renders the list. Charts are CSS bars, with no chart library.
**Consequences:** The AG-UI phase replaces the layout list at runtime and adds an agent, without
touching the components.

### 2026-10-14 — "Troubled" means followed by an interrupt, not by a tool error

**Status:** Accepted
**Context:** On local data a tool error follows 39.8% of all tool calls within 15 minutes, so tool
errors flagged almost every busy skill. An interrupt follows 4.5%.
**Decision:** `troubled` needs at least 3 uses in the last 30 days, and at least 20% of them
followed by an `interrupt` in the same session within 15 minutes. The numbers are constants in
`aggregate.py`.
**Consequences:** 13 flagged skills on local data dropped to 4. Tool errors stay in the store for a
later rule.

### 2026-10-14 — A project is labelled by its launch folder

**Status:** Accepted
**Context:** Labelling a project by its latest `cwd` renamed a project whenever a session moved into
a subfolder.
**Decision:** The label is the basename of the `cwd` that encodes to the project folder name, else
the latest `cwd`, else the encoded folder name. Two projects with the same basename get the folder
name appended.
**Consequences:** Labels stay stable as sessions move around inside a repo.
