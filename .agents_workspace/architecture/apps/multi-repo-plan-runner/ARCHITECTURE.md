# docket — Architecture

A local command-center over many Claude Code repos: read plans from each repo's
`.agents_workspace/planning/`, track each plan's lifecycle in a JSON sidecar, and implement
plans (manually or headless via `claude -p`) from a Textual TUI or a localhost browser page.

## System context

External actors and systems around docket's boundary.

```mermaid
flowchart LR
    you([You]) -->|generate / --merge| init["docket init<br/>(scaffold .docket.json)"]
    init --> registry[".docket.json<br/>(registry: app · defaults · projects)"]
    you -->|hand-edit| registry
    you -->|check| doctor["docket doctor<br/>(config sanity)"]
    you -->|author| plans[".agents_workspace/planning/**.md<br/>(plans — read-only to docket)"]
    you -->|use| tui["docket tui"]
    you -->|browser| server["docket serve<br/>127.0.0.1"]

    schema["docket/schema/docket.schema.json<br/>(shipped; editor autocomplete)"] -. $schema .-> registry
    registry --> docket((docket))
    doctor --> registry
    plans --> docket
    tui --- docket
    server --- docket
    docket -->|own| sidecar[".agents_workspace/implementation/**.json<br/>(status + history)"]
    docket -->|spawn `claude -p` in repo| cc["Claude Code CLI<br/>(BYO, authenticated)"]
```

## Components

Two thin frontends over one shared core + tracker; the only subprocess is the headless runner.

```mermaid
flowchart TD
    subgraph frontends
        tui["tui.py<br/>Textual app (worker thread)"]
        server["server.py<br/>ThreadingHTTPServer + SSE"]
        static["static/<br/>index.html · app.js · style.css"]
    end
    core["core.py<br/>load_registry (layer cascade → Config) · plan discovery · safe_slug<br/>manual_command · run_implement · resolve_instruction<br/>cmd_init · discover_repos · cmd_doctor"]
    rm["RunManager (server side)<br/>group-by-project · sequential per project<br/>concurrent across · stop-on-failure"]
    lock["per-project lock<br/>dict[path]→Lock"]
    tracker["tracker.py<br/>sidecar read/write · ALLOWED table<br/>atomic write · reset_stale_runs"]
    fm["frontmatter.py<br/>read-only title extraction"]
    cc["claude -p<br/>--output-format stream-json"]

    server --> static
    tui -.->|import| core
    server -.->|import| core
    server --> rm --> core
    core --> lock
    core --> fm
    core -->|set_status| tracker
    core -->|spawn cwd=repo| cc
    tracker -->|JSON| sidecar[".agents_workspace/implementation/"]
    core -->|read-only| plans[".agents_workspace/planning/"]
```

## Key flow — headless implement

The one subprocess path: instruction (naming the plan file) is piped on stdin; the plan body is
never piped — Claude Code opens the file itself.

```mermaid
sequenceDiagram
    participant UI as Frontend
    participant RM as RunManager
    participant Core as run_implement
    participant Tr as tracker
    participant CC as claude -p

    UI->>RM: submit([{project, slug, instruction?}])
    RM->>RM: validate + create Run(queued) per item
    RM-->>UI: run_ids (open SSE per id)
    RM->>Core: run_implement (per-project thread, sequential)
    Core->>Core: acquire project lock
    Core->>Tr: set_status(running, trigger=headless)
    Core->>CC: spawn (cwd=repo), pipe instruction on stdin
    loop stream-json events
        CC-->>Core: NDJSON event
        Core-->>UI: format_event line (via queue → SSE)
    end
    CC-->>Core: exit rc
    Core->>Tr: set_status(implemented if rc==0 else ready)
    Core->>Core: release lock
    Core-->>UI: end event (done/failed/stopped/skipped)
```

## Data model

Persisted: Project (registry) and Sidecar (docket-owned). In-memory only: Run and Batch. Plan is
a read-only view of a markdown file plus its sidecar status.

```mermaid
erDiagram
    CONFIG ||--o{ PROJECT : "resolves (cascade)"
    PROJECT ||--o{ PLAN : "discovers"
    PLAN ||--|| SIDECAR : "status from"
    SIDECAR ||--o{ TRANSITION : "history"
    BATCH ||--|{ RUN : "groups by project"
    RUN }o--|| PLAN : "implements"

    CONFIG {
        int port "app-level; --port flag overrides"
        list projects
    }
    PROJECT {
        string name PK
        string path "~ and $VARS expanded → abspath"
        list allowed_tools
        string instruction_template
        string model
        int max_turns
        string permission_mode "acceptEdits|default|plan|bypassPermissions"
        string planning_dir
        string implementation_dir
        string claude_bin
        list claude_extra_args
    }
    PLAN {
        string slug "rel path under planning/, sans .md"
        string title "from frontmatter, else slug"
        string body "read-only markdown"
    }
    SIDECAR {
        string slug
        string status "ready|running|implemented"
    }
    TRANSITION {
        string ts "ISO-8601 UTC"
        string from
        string to
        string trigger "headless|manual|startup_reset"
        string run_id
        int rc
    }
    RUN {
        string run_id "uuid4 hex"
        string state "queued|running|done|failed|stopped|skipped"
    }
```

## Lifecycle state machine

Status lives only in the sidecar; the tracker rejects any edge not drawn here.

```mermaid
stateDiagram-v2
    [*] --> ready
    ready --> running : headless spawn
    running --> implemented : headless rc==0
    running --> ready : headless fail/stop / startup_reset
    ready --> implemented : manual mark
    implemented --> ready : manual reopen
```

Only `ready` is runnable: `run_implement` and `RunManager.submit` reject any other status, and there
is no `implemented → running` edge. Re-implementing an implemented plan requires a manual reopen
(`implemented → ready`) first — see the 2026-07-02 decision.

## Key Decisions

### 2026-06-20 — Three-layer config in .docket.json, resolved at load (v2)

**Status:** Accepted
**Context:** v1 hardcoded most knobs (allowed_tools, model, max_turns, permission mode, the
planning/implementation dirs, the claude binary) and read a flat `projects.json`. Managing ~10
repos needs per-project overrides without per-repo code, and the registry should be the whole
config.
**Decision:** Rename the registry to `.docket.json` and give it three tiers — top-level app
settings (`port`), a `defaults` layer, and `projects[]` overrides. `load_registry` merges them
per-knob (`CODE_DEFAULTS` → `defaults.<k>` → `project.<k>`) into resolved `Project` fields and
returns a `Config`; every downstream reader stays unchanged in shape. The loader is **not**
cached so a changed `--registry`/`$DOCKET_REGISTRY` is always re-read. No automatic migration
from `projects.json` (a top-level `instruction_template` is leniently promoted into `defaults`).
The instruction template keeps a 4th, highest layer: the per-plan override at submit time.
**Consequences:** Every knob is configurable with a global baseline and per-project overrides;
list overrides replace (not merge). `run_implement` preflights `claude_bin` before flipping
status/taking the lock so a bad binary fails cleanly.

### 2026-06-20 — `docket init` scaffolds config; JSON Schema is editor-side only (v2)

**Status:** Accepted
**Context:** A complete `.docket.json` is tedious to hand-author and easy to mistype. Runtime
JSON-Schema validation would add a dependency against the "stdlib-only" decision below.
**Decision:** Ship `docket init [--scan ROOT] [--force|--merge] [--dry-run]` to generate a full
default config (or `--merge` only newly-discovered repos in place, the re-run path as repos
drift) and `docket doctor` to sanity-check it (paths, dupes, planning dir, `permission_mode`,
`claude_bin` on PATH). Ship a JSON Schema (`docket/schema/docket.schema.json`) as package data,
pointed at by the generated `$schema` — consumed by editors only. Runtime loading stays lenient
stdlib checks and never reads the schema.
**Consequences:** No blank-page authoring and no new dependency; `doctor`'s exit code (1 on any
error-level finding) makes it usable as a pre-run gate. The `$schema` pointer is machine-specific
when written absolute by `init` — rerun `init` if the install moves.

### 2026-06-20 — Stdlib http.server + JSON, no web framework or DB

**Status:** Accepted
**Context:** A local single-user tool over ~10 repos. Options: FastAPI/Flask + a database, or
pure stdlib. The data is tiny (a registry and one small JSON sidecar per plan).
**Decision:** Use stdlib `http.server.ThreadingHTTPServer` with hand-written HTML/CSS/JS and
stdlib `json` for the registry and sidecars. No FastAPI/Flask, no database, no YAML/TOML, no
build step. The only pip dependency is `textual` (TUI); the browser side is pure stdlib.
**Consequences:** Zero infra and trivial install, at the cost of writing routing/SSE by hand.
Acceptable for the scale; not intended to serve multiple users or large data.

### 2026-06-20 — Plans are read-only; status is a derived JSON sidecar

**Status:** Accepted
**Context:** Plans are authored externally by the planning skill and may carry their own
`status:` frontmatter (a document state, not a lifecycle state). docket needs mutable lifecycle
state without ever risking a plan file.
**Decision:** docket never creates/edits/deletes plan files. Lifecycle status + full transition
history live in a separate sidecar under `.agents_workspace/implementation/`, mirroring the
plan's relative path. A missing sidecar means `ready` with empty history. The plan's own
`status:` is ignored.
**Consequences:** Deleting `implementation/` loses only status/history, never a plan. Two
distinct "status" notions coexist; code reads lifecycle status exclusively from the sidecar.

### 2026-06-20 — Headless run pipes the instruction, not the plan body

**Status:** Accepted
**Context:** The headless path must hand a plan to `claude -p`. Piping the full plan body bloats
stdin and breaks cross-file references (a plan may reference its SKELETON / earlier iterations).
**Decision:** Pipe a short instruction on stdin that *names the plan file*
(`.agents_workspace/planning/<slug>.md`); Claude Code opens and reads it (and any siblings)
itself. The instruction comes from the resolved `project.instruction_template` (config cascade:
`defaults` → `DEFAULT_INSTRUCTION_TEMPLATE`) with `{path}` substituted, overridable per plan at
submit time. Each headless run is a brand-new session with fresh instruction text (re-running a
plan first requires a manual reopen — see the 2026-07-02 decision).
**Consequences:** Tiny stdin, full sibling-file access, per-plan instructions, clean sessions.
docket builds no message array and manages no context window — Claude Code owns the conversation.

### 2026-06-20 — In-memory runs, per-project lock, startup reset for recovery

**Status:** Accepted
**Context:** Concurrent headless runs on the same repo would collide in the working tree. Runs
must stream live and survive a crash without stranding a plan at `running`.
**Decision:** A per-project `threading.Lock` (setdefault-guarded dict) serializes same-repo runs;
different projects run concurrently. Runs/batches are in-memory only (never persisted). On
startup both frontends call `reset_stale_runs`, flipping any sidecar reading `running` back to
`ready` (trigger=`startup_reset`). The browser server binds to `127.0.0.1` only — the auth story.
**Consequences:** A crash can't strand a plan. The lock is intra-process only: running the TUI
and server against the same repo simultaneously is not cross-process-locked (documented MVP
limitation). Live run output is not persisted — only status transitions are.

### 2026-06-20 — Atomic sidecar write via os.replace, with a Windows retry

**Status:** Accepted
**Context:** A crash mid-write must never leave a half-written sidecar. On Windows a
just-written target is transiently locked by Defender/indexer, which deterministically broke the
immediate overwrite with `PermissionError (WinError 5)`.
**Decision:** Write to a temp file in the same directory, then `os.replace` over the target
(atomic on one filesystem). Wrap the replace in a bounded retry (10× @ 50ms) on `PermissionError`
to tolerate the transient Windows lock.
**Consequences:** Crash-safe writes on all platforms; a contended write may block up to ~0.5s
before raising on Windows. No new dependency.

### 2026-07-02 — Only `ready` is runnable; implemented plans must be reopened to re-run

**Status:** Accepted
**Context:** `run_implement`, `RunManager.submit`, and both frontends treated `implemented` as
re-runnable (`status in ("ready", "implemented")`), and the lifecycle table declared
`("implemented", "running"): {"headless"}` legal. This let a user launch Implement — single or
batch — on a plan already marked implemented, both from the TUI and the browser, which is
surprising and risks re-running finished work.
**Decision:** Make `ready` the sole runnable status. `run_implement` and `submit` now reject any
non-`ready` status; the `implemented → running` edge was removed from `tracker.ALLOWED` so the
state machine itself forbids it. The frontends mirror the rule: the webui disables the Implement
button and the batch checkbox for non-`ready` plans, and the TUI's `action_implement` and
`action_toggle_select` refuse non-`ready` plans with a log message. Re-implementing is still
possible via the existing manual reopen (`implemented → ready`), then `ready → running` — this
reverses the "clean re-runs from implemented" consequence of the 2026-06-20 "pipes instruction"
decision without touching its core (instruction-not-body still holds).
**Consequences:** Re-running a finished plan is now a deliberate two-step (reopen, then implement)
rather than a single click. `run_myself` (manual, never goes through `run_implement`) is
unaffected and stays available for implemented plans; only `running` disables it. Core is the
authoritative guard — the UI gating is UX, not the enforcement boundary.
