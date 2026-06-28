# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

docket is a local, single-user command-center over ~10 Claude Code repos. It reads plan
markdown files from each repo's `.agents_workspace/planning/`, tracks each plan's lifecycle in a
docket-owned JSON sidecar, and implements plans — manually or headless via `claude -p` — from a
Textual TUI or a localhost browser page. Python 3.11+; the only pip dependency is `textual` (the
browser side is pure stdlib).

## Commands

Prefer `uv` for everything (it reads the committed `uv.lock`). Only if `uv` is not installed or
fails to run, fall back to the standard `pip`/`python` tooling.

```
uv sync                          # install   (fallback: pip install -e .)
uv run docket tui                # Textual terminal UI            (fallback: docket tui)
uv run docket serve --port 8765  # localhost browser page         (fallback: docket serve --port 8765)
                                 # -> http://127.0.0.1:8765
uv run docket init --scan ~/code # scaffold/refresh .docket.json  (--merge to add new repos in place)
uv run docket doctor             # sanity-check the resolved config (exit 1 on any error)
uv run pytest                    # test suite (100% coverage gate via --cov, configured in pyproject)
```

Both subcommands accept `--registry PATH`. A pytest suite lives under `tests/` (`unit/` +
`api/`) and is kept at 100% line+branch coverage — per the contract, do not add tests unless
asked, but if you change `docket/` keep the suite green and coverage at 100%. No linter step
exists. For a quick sanity check on an edit, parse/type-check the changed file
(`uv run python -m py_compile <file>`, fallback `python -m py_compile <file>`). The headless
runner shells out to `claude` (BYO-CLI, must be installed and authenticated); docket never
handles API keys.

Registry resolution (first match wins): `--registry PATH` → `$DOCKET_REGISTRY` →
`./.docket.json` → `~/.config/docket/.docket.json`. The registry has three layers (top-level app
settings · `defaults` · `projects[]`); `load_registry` merges them per-knob
(`CODE_DEFAULTS` → `defaults.<k>` → `project.<k>`) into a `Config` of resolved `Project`s.

## Architecture

Two thin frontends over one shared core. Read
`../../.agents_workspace/archive/multi-repo-plan-runner-architecture.md` (archived at the repo
root) for the full diagrams + Key Decisions log before any structural change.

- `core.py` — registry load, plan discovery/read, `safe_slug`, `manual_command`, `resolve_instruction`, the headless `run_implement` generator, and the server-side `RunManager` (batch orchestration). The only subprocess (`claude -p`) lives here.
- `tracker.py` — the implementation sidecar: lifecycle status + transition history. Owns the `ALLOWED` transition table, atomic writes, and `reset_stale_runs` (startup recovery).
- `frontmatter.py` — lenient, **read-only** flat-key frontmatter reader; docket only needs `title`. There is intentionally no `dump`.
- `tui.py` — Textual app; streams one run at a time (MVP).
- `server.py` + `static/` — stdlib `ThreadingHTTPServer` + hand-written JSON API + SSE; hand-written HTML/CSS/JS, no framework, no build. Binds `127.0.0.1` only — that is the entire auth story.

Layer boundary: both frontends import `core`; `core` calls `tracker`/`frontmatter`; status is read
and written **only** through `tracker`. Keep business logic out of the route handlers in
`server.py` — they validate and call `core`/`tracker`.

## Invariants — do not break these

These are load-bearing; several are documented as accepted decisions in the archived
architecture doc (`../../.agents_workspace/archive/multi-repo-plan-runner-architecture.md`).

- **Plans are read-only to docket.** Never create, edit, or delete anything under `planning/`. All mutable state is the sidecar under `.agents_workspace/implementation/<slug>.json`. A plan's own `status:` frontmatter is ignored — lifecycle status comes exclusively from the sidecar; a missing sidecar means `ready`.
- **Lifecycle status is a closed set** `ready | running | implemented` with a fixed transition table (`tracker.ALLOWED`, keyed by `(from, to) -> {triggers}`). Never bypass `tracker.set_status` to change status, and never add an edge without adding it to that table. The state machine is drawn in the archived architecture doc.
- **The headless run pipes the instruction, not the plan body.** stdin gets a short instruction that *names* the plan file (`.agents_workspace/planning/<slug>.md`); Claude Code opens it (and any siblings) itself. Do not pipe the plan body. Instruction comes from `instruction_template` (registry) → `DEFAULT_INSTRUCTION_TEMPLATE`, with `{path}` substituted, overridable per submit.
- **Every external slug goes through `core.safe_slug`** before becoming a path or query value — it is the path-traversal guard that keeps access inside `planning/`/`implementation/`.
- **Per-project `threading.Lock`** serializes same-repo headless runs (different projects run concurrently). It is intra-process only — not cross-process locked (documented MVP limitation). Runs/batches are in-memory only, never persisted.
- **Sidecar writes are atomic** (`tracker._atomic_write`: temp file + `os.replace`) with a bounded Windows retry on `PermissionError` (AV/indexer transiently locks the just-written target). Preserve both the atomicity and the retry when touching this.

## Conventions

- Decisions: this member's historical build decisions are archived in the repo-root
  `.agents_workspace/archive/decision-log.md`; new decisions go in the repo-root
  `.agents_workspace/DECISION_LOG.md`. (Note: the `.agents_workspace/planning/` and
  `.agents_workspace/implementation/` paths elsewhere in this file refer to the **target
  repos** docket operates on, not this repo.)
- Primary dev platform is Windows (PowerShell); a Bash tool is also available. Code must stay cross-platform.
