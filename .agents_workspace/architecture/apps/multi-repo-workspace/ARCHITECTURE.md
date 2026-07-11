# roundtable (`apps/multi-repo-workspace`) — Architecture

A local, single-user, turn-based workspace over many Claude Code repos: a board of repos with live git/plan state, in-app `claude -p` planning sessions, rounds of orders executed headlessly (End Turn), and a review phase with diffs, commits, and follow-ups carried to the next round. Successor to docket (`apps/multi-repo-plan-runner`), which stays untouched and standalone.

## System context

External actors and systems around roundtable's boundary.

```mermaid
flowchart LR
    you([You]) -->|scaffold / --scan| init["roundtable init"]
    init --> registry[".roundtable.json<br/>(registry: app · defaults · projects)"]
    you -->|hand-edit| registry
    you -->|check| doctor["roundtable doctor"]
    you -->|browser| server["roundtable serve<br/>127.0.0.1:8640"]

    schema["roundtable/schema/roundtable.schema.json<br/>(shipped; editor autocomplete)"] -. $schema .-> registry
    registry --> rt((roundtable))
    doctor --> registry
    server --- rt
    rt -->|read-only| plans[".agents_workspace/planning/**.md<br/>(plans — written by Claude, never the app)"]
    rt -->|own| sidecar[".agents_workspace/implementation/**.json<br/>(lifecycle sidecars — docket-compatible)"]
    rt -->|own| home["~/.roundtable/<br/>(rounds · session transcripts · run output)"]
    rt -->|spawn `claude -p` in repo| cc["Claude Code CLI<br/>(BYO, authenticated)"]
    rt -->|read git · commit on request| git["git CLI"]
```

## Components

One stdlib HTTP server over core modules; `server.py` is transport only (validate + delegate).

```mermaid
flowchart TD
    static["static/<br/>vanilla JS · hash routes · 5s board poll<br/>vendored marked + DOMPurify"] --- server
    server["server.py<br/>ThreadingHTTPServer · JSON API · SSE · 501 map"]
    server --> registry["registry.py<br/>3-layer cascade → Config · init · doctor<br/>atomic_write_json · read_json (retry)"]
    server --> gitinfo["gitinfo.py<br/>read-only git: branch · dirty · log · diff · tree<br/>file read/save (_resolve_inside)"]
    server --> plans["plans.py + frontmatter.py<br/>discovery · safe_slug · title"]
    server --> sessions["sessions.py<br/>SessionManager: claude -p + --resume<br/>transcript persist · produced-plan detection"]
    server --> rounds["rounds.py<br/>round/order store + state machines"]
    server --> gitwrite["gitwrite.py<br/>add -A + commit (the only git write)"]
    rounds --> executor["executor.py<br/>End Turn: thread per repo · sequential within"]
    plans --> tracker["tracker.py<br/>sidecar status + ALLOWED table"]
    executor --> tracker
    sessions --> locks["locks.py<br/>per-project Lock (intra-process)"]
    executor --> locks
    gitwrite --> locks
    sessions --> costs["costs.py<br/>claude-usage estimate (canonical)"]
    executor --> costs
    sessions -->|spawn| cc["claude -p --output-format stream-json"]
    executor -->|spawn| cc
```

## Key flow — planning turn

A multi-turn chat with Claude running inside the target repo; the plan file Claude writes is detected by snapshotting the planning dir around the turn.

```mermaid
sequenceDiagram
    participant UI as #35;/session/{id}
    participant SM as SessionManager
    participant CC as claude -p

    UI->>SM: POST /api/sessions/{id}/message
    SM->>SM: acquire project lock · idle → streaming
    SM->>SM: snapshot planning_dir (before)
    SM->>CC: spawn (cwd=repo), turn 1 fresh / turn N --resume sid
    loop stream-json events
        CC-->>SM: NDJSON event
        SM-->>UI: token via per-session Queue → SSE (15s pings)
    end
    CC-->>SM: result event (usage · total_cost_usd)
    SM->>SM: estimate cost (claude-usage) · persist transcript + meta
    SM->>SM: snapshot planning_dir (after) → produced plans
    SM->>SM: streaming → idle · release lock
    SM-->>UI: turn-end event (produced plans · cost)
```

## Key flow — End Turn

All queued orders execute: sequential within a repo (stop-on-failure), concurrent across repos, output persisted and streamed live.

```mermaid
sequenceDiagram
    participant UI as #35;/round
    participant R as rounds.py
    participant Ex as executor.py
    participant Tr as tracker
    participant CC as claude -p

    UI->>R: POST /api/rounds/current/end-turn
    R->>R: open → executing (trigger end_turn)
    R->>Ex: execute(round) — one thread per project
    par per project (concurrent)
        Ex->>Ex: acquire project lock
        loop orders of that project (sequential)
            Ex->>Tr: ready → running (trigger round)
            Ex->>CC: spawn (cwd=repo), pipe instruction naming {path}
            CC-->>Ex: NDJSON → rounds/<rnd_id>/<ord_id>.ndjson + SSE
            Ex->>Tr: running → implemented (rc==0) / ready
            Ex->>Ex: queued → skipped for the rest on failure
        end
        Ex->>Ex: release lock
    end
    Ex->>R: last order terminal → executing → review (all_terminal)
```

## Data model

Persisted: Project (registry), Sidecar (in-repo), PlanningSession and Round/Order (under `~/.roundtable/`). Plan is a read-only view of a markdown file plus its sidecar status. Round cost is computed at read time, never stored.

```mermaid
erDiagram
    CONFIG ||--o{ PROJECT : "resolves (cascade)"
    PROJECT ||--o{ PLAN : "discovers"
    PLAN ||--|| SIDECAR : "status from"
    SIDECAR ||--o{ TRANSITION : "history"
    PROJECT ||--o{ SESSION : "plans in"
    ROUND ||--o{ ORDER : "queues"
    ORDER }o--|| PLAN : "implements"
    ROUND ||--o{ CARRIED : "inherits at close"

    PROJECT {
        string name PK
        string path
        string planning_dir
        string implementation_dir
        string permission_mode
        string planning_permission_mode
        string instruction_template "{path} substituted"
        string planning_template "{request} {planning_dir}"
    }
    SIDECAR {
        string status "ready|running|implemented"
    }
    TRANSITION {
        string trigger "round|manual|startup_reset (opaque)"
    }
    SESSION {
        string id PK "ps_ prefix"
        string status "idle|streaming|closed|failed"
        string claude_session_id "--resume handle"
        string transcript "ndjson sidecar file"
    }
    ROUND {
        string id PK "rnd_ prefix"
        int number
        string status "open|executing|review|done"
    }
    ORDER {
        string id PK "ord_ prefix"
        string state "queued|running|succeeded|failed|stopped|skipped"
        bool reviewed "mutable in review only"
        string followup "2KB cap, carried at close"
    }
    CARRIED {
        int from_round
        string note
    }
```

## State machines

Closed sets with validated transition tables; any edge not drawn is rejected (409). Plan lifecycle (sidecar, `tracker.ALLOWED` — trigger on the edge):

```mermaid
stateDiagram-v2
    [*] --> ready
    ready --> running : round
    running --> implemented : round rc==0
    running --> ready : round fail/stop / startup_reset
    ready --> implemented : manual
    implemented --> ready : manual
```

Planning session (`sessions.ALLOWED`; `closed`/`failed` terminal):

```mermaid
stateDiagram-v2
    [*] --> idle
    idle --> streaming : message
    streaming --> idle : turn end / stop
    streaming --> failed : spawn/parse fatal
    idle --> closed : close
```

Round (`rounds.ROUND_ALLOWED`) and order (`rounds.ORDER_ALLOWED`):

```mermaid
stateDiagram-v2
    [*] --> open
    open --> executing : end_turn
    executing --> review : all_terminal / stop / startup_reset
    review --> done : close (opens Round N+1)
```

```mermaid
stateDiagram-v2
    [*] --> queued
    queued --> running
    queued --> failed : claude_bin preflight
    queued --> skipped : earlier same-repo failure / stop
    running --> succeeded
    running --> failed
    running --> stopped
```

## Key Decisions

### 2026-07-10 — Successor app, not a docket rewrite; sidecar format is the shared contract

**Status:** Accepted
**Context:** docket runs externally-authored plans; the wanted workflow adds in-app planning, rounds, and review. Options: grow docket (bloats a shipped tool, TUI parity drag), extract a shared library (violates the repo's ≥2-consumer/cohesion bar for `libs/` — the overlap is a file format, not a domain), or a new member.
**Decision:** New member `apps/multi-repo-workspace` (roundtable); docket stays untouched and useful standalone. The only shared surface is the on-disk lifecycle sidecar format (same keys, location, statuses), kept in sync by hand — registered in `docs/shared-plugin-logic.md` with `Cross-reference:` comments in both trackers (the one sanctioned docket edit). Trigger vocabularies deliberately differ (`round` vs `headless`); both sides treat `trigger` as an opaque display string, so histories interleave.
**Consequences:** Both apps can point at the same repos without fighting. Plan discovery/frontmatter code is forked at birth (marked in module docstrings), accepted as intentional duplication; if a third consumer appears, revisit extraction.

### 2026-07-10 — Stdlib server + vanilla JS; the only non-stdlib pieces are claude-usage and two vendored JS assets

**Status:** Accepted
**Context:** Same scale as docket (local, single user, ~10 repos, tiny data). Full markdown rendering (headings/tables/code in plans, transcripts) is wanted; hand-rolling CommonMark would exceed the wrapper it replaces.
**Decision:** stdlib `ThreadingHTTPServer` + hand-written JSON API + SSE (native `EventSource`; GET endpoints), vanilla JS with hash routes, 5s board polling with SSE reserved for live streams. Python deps: exactly one, the in-repo stdlib-only `claude-usage` (cost estimation). Frontend: vendored, pinned single-file `marked` + `DOMPurify` under `static/vendor/` (upstream license headers retained) — no npm, no build step. All fetches through `js/api.js`; all markdown through `js/markdown.js`.
**Consequences:** Zero infra, trivial install; routing/SSE written by hand. Vendored assets are upgraded manually. Not intended for multiple users or large data.

### 2026-07-10 — Plans are app-read-only; exactly three sanctioned writes into a target repo

**Status:** Accepted
**Context:** roundtable both surfaces repos and lets Claude plan inside them; an app that edits plan files risks clobbering externally-authored artifacts (docket's founding invariant, now with more write-capable surfaces).
**Decision:** The app never creates, edits, or deletes a plan file. Writes into a target repo are limited to: (1) the spawned Claude planning session writing the plan itself, (2) the file editor's explicit Save (PUT with optimistic concurrency), (3) the explicit Commit (`gitwrite.py`: `add -A` + `commit`, argv no shell, no push/branch/amend — quarantined as the only git write). Everything else the app owns lives in sidecars and `~/.roundtable/`. Every externally-supplied slug passes `safe_slug`; every file path passes a realpath containment check.
**Consequences:** Deleting `~/.roundtable/` or `implementation/` loses only app state, never a plan. Commit stays locally reversible; review-to-PR automation is post-MVP.

### 2026-07-10 — Instruction-not-body for every spawn; the CLI owns conversation state

**Status:** Accepted
**Context:** Both planning turns and implement runs must hand context to `claude -p`. Piping plan bodies bloats stdin and breaks sibling-file references; managing message arrays in-app duplicates what the CLI already does.
**Decision:** Implement runs pipe a short instruction that names the plan file (`instruction_template`, `{path}` substituted). Planning turn 1 pipes `planning_template` (`{request}`, `{planning_dir}`); later turns pipe the user's message verbatim with `--resume <session_id>` carrying context. Produced plans are detected by snapshotting the planning dir before/after each turn — filesystem truth, not model claims.
**Consequences:** Tiny stdin, full repo access for Claude, no in-app context-window management. A session that outgrows the CLI's context is handled by starting a fresh session (documented limitation).

### 2026-07-10 — Pricing-table estimate is the canonical cost; CLI total_cost_usd is secondary

**Status:** Accepted
**Context:** Two cost sources per run: `claude-usage`'s pricing-table estimate over reported token counts, and the CLI's own `total_cost_usd`. They can disagree, and the CLI figure's basis is opaque.
**Decision:** Every displayed cost is the estimate (`claude_usage.estimated_cost`); `total_cost_usd` is stored and shown only as an informational secondary figure. A model missing from the pricing table renders "n/a" (`null`), never $0. Round cost is rolled up at read time from per-order figures, never stored.
**Consequences:** Costs are consistent with `usage-dashboard`/`usage-report` (same library and table). Estimates drift when the pricing table lags a new model — visible as "n/a" rather than a wrong number.

### 2026-07-10 — One per-project lock shared by every repo-touching surface; persisted state + startup recovery

**Status:** Accepted
**Context:** Planning turns, implement runs, file saves, and commits can all touch the same working tree; docket's crash-recovery lesson (never strand `running`) now applies to sessions and rounds too, and rounds/transcripts must survive restarts (unlike docket's in-memory runs).
**Decision:** A single `locks.py` dict of per-project `threading.Lock`s serializes all of the above per repo (intra-process only — documented MVP limitation, same as docket). Sessions, rounds, and run output are persisted under `~/.roundtable/` as JSON/NDJSON; all JSON writes are atomic (temp + `os.replace` + bounded Windows retry) and hot reads go through a bounded-retry reader. On startup: `running` sidecars reset to `ready`, `streaming` sessions to `idle` with a synthetic `interrupted` transcript event, and a round stuck `executing` to `review` (running orders → `stopped`, queued → `skipped`; trigger `startup_reset`).
**Consequences:** A crash can't strand any state machine; history and costs survive restarts. Two server processes against the same repo are not cross-process-locked.
