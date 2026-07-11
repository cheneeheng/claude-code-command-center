# CLAUDE.md

Guidance for Claude Code when working in `apps/multi-repo-workspace` (internal name **roundtable**).

## What this is

A stdlib-only localhost web app: a turn-based board over multiple Claude Code repos — browse repos, run in-app `claude -p` planning sessions, queue plan orders into rounds, execute them headlessly (End Turn), review/commit, close the round. See README.md for the full loop and configuration.

## Running

`uv run roundtable serve` (default `127.0.0.1:8640`); `roundtable init [--scan ROOT]` scaffolds `.roundtable.json`; `roundtable doctor` checks it. Env: `C4_ROUNDTABLE_REGISTRY` (registry path), `C4_ROUNDTABLE_HOME` (state dir, default `~/.roundtable/`).

## Architecture (one line each)

`server.py` HTTP transport only → core modules: `registry.py` (3-layer config cascade + init/doctor + atomic IO), `gitinfo.py` (read-only git + file browse/edit), `plans.py`/`frontmatter.py` (read-only plan discovery), `tracker.py` (lifecycle sidecars), `sessions.py` (planning sessions), `rounds.py` (round/order store + state machines), `executor.py` (End-Turn batch runner), `gitwrite.py` (commit — the only git write), `locks.py` (per-project locks). Frontend: `static/` vanilla JS, hash routes, 5s board poll + SSE for live streams only.

## Invariants — do not break these

- **Plans are app-read-only.** roundtable never creates, edits, or deletes a plan file. The only writes into a target repo are: the spawned Claude planning session writing the plan, the file editor's explicit Save, and the explicit Commit. Everything else the app owns lives in the sidecars and `~/.roundtable/`.
- **Closed status sets with validated transition tables.** Sidecar `ready|running|implemented` (`tracker.ALLOWED`), session `idle|streaming|closed|failed` (`sessions.ALLOWED`), round `open|executing|review|done` (`rounds.ROUND_ALLOWED`), order `queued|running|succeeded|failed|stopped|skipped` (`rounds.ORDER_ALLOWED`). Never accept a free-form status string; never add an edge without updating the table and its tests.
- **The sidecar format is a kept-in-sync contract with docket** (`apps/multi-repo-plan-runner/docket/tracker.py`): same keys, same location (`<implementation_dir>/<slug>.json`), same statuses. Registered in `docs/shared-plugin-logic.md`; change both sides together or not at all. Trigger vocabulary is the one sanctioned divergence (opaque display string).
- **Instruction, not body.** Implement runs pipe a short instruction that *names* the plan file (`{path}`); the plan body is never piped. Planning turn 1 uses `planning_template`; later turns are the user's message verbatim (`--resume` carries context).
- **`safe_slug` on every externally-supplied slug** (path traversal guard), `_resolve_inside`-style realpath checks on every file path. Route handlers validate and delegate; no business logic in `server.py`; status mutations only through `tracker`/`rounds`.
- **Per-project lock is intra-process only** (documented MVP limitation). Planning turns, implement runs, file save, and commit all respect it.
- **All JSON state writes are atomic** (`registry.atomic_write_*`: temp file + `os.replace` + bounded Windows retry); reads of hot files go through `registry.read_json` (bounded retry). Round cost is computed at read time, never stored.
- **Cost policy: the pricing-table estimate is canonical** (`claude_usage.estimated_cost`); the CLI's `total_cost_usd` is secondary/informational. Unknown model ⇒ `null` ⇒ "n/a", never 0.
- **Frontend:** all fetches through `js/api.js`; all markdown through `js/markdown.js` (marked → DOMPurify, no second renderer); native `EventSource` for SSE (endpoints stay GET with path/query params); controls appear only when functional — no disabled placeholders.

## Conventions

- `uv`-managed; ruff (line 88) + `ruff format`; `mypy --strict`; pytest with a **100% line+branch coverage gate** over `roundtable/` — new code lands with the tests that keep the gate green. `tests/smoke.sh` boots the real server against a fake `claude`.
- Public IDs: `{prefix}_{secrets.token_urlsafe(12)}` (`rnd_`, `ord_`, `ps_`); IDs and `created_at` never change.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
