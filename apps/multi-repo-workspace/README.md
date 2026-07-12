# roundtable

A local, single-user, **turn-based workspace** over the ~10 Claude Code repos you work across. The mental model is a strategy game, not a shooter: each repo is a city on a board, and work advances in **rounds**. In a round you survey the board (git state, plans, last round's outcomes), open repos to **plan with Claude Code in a chat panel** (Claude writes the plan file into that repo's `.agents_workspace/planning/`), queue **orders** (repo + plan pairs), then hit **End Turn**: all orders execute headlessly (`claude -p`), sequentially per repo and concurrently across repos, with live streams. The round then enters **review** — per-repo output replay, working-tree diffs, optional commit, follow-up notes — and closing it opens the next round with the follow-ups carried over.

roundtable is the successor to [docket](../multi-repo-plan-runner/) (`apps/multi-repo-plan-runner`): where docket only *runs* externally-authored plans, roundtable is a full workspace — browse repos, plan with Claude inside the app, and execute plans from one board. Both apps read and write the **same lifecycle sidecar format**, so they can point at the same repos without fighting (see [shared logic](../../docs/shared-plugin-logic.md)).

The core flow: **board → open repo → plan with Claude → add order → End Turn → watch streams → review diffs → commit → close round → next round.**

## Requirements

- Python **3.12+**, managed with [`uv`](https://docs.astral.sh/uv/).
- The `claude` CLI on PATH, authenticated (BYO — roundtable shells out to it and never touches API keys).
- `git` on PATH.
- A browser. The server binds `127.0.0.1` only; that is the entire auth story.

The only Python dependency is the in-repo, stdlib-only [`claude-usage`](../../libs/claude-usage/) library (cost estimation). The frontend is framework-free vanilla JS with two vendored, pinned single-file assets ([marked](https://github.com/markedjs/marked), MIT; [DOMPurify](https://github.com/cure53/DOMPurify), Apache-2.0/MPL-2.0 — upstream license headers retained in `roundtable/static/vendor/`). No npm, no build step.

## Quick start

See it working immediately, no setup — from this directory (`apps/multi-repo-workspace/`):

```bash
uv run roundtable --registry examples/roundtable.json serve
```

then open http://127.0.0.1:8640. That loads the [runnable example](examples/README.md): two sample repos with plans and a ready-made registry (the sample repos are not git repos, so their cards show a git warning strip — expected).

For your own repos:

```bash
uv run roundtable init --scan ~/repos   # discover repos with a planning dir -> .roundtable.json
uv run roundtable doctor                # sanity-check paths, modes, claude/git on PATH
uv run roundtable serve                 # http://127.0.0.1:8640
```

## The round loop

1. **Board** (`#/board`) — one card per registered repo: branch, dirty count, ahead/behind, last commit, plan counts by status, live round/session activity. Click a card to open the repo.
2. **Repo detail** (`#/repo/{name}`) — tabs: **Plans** (with lifecycle status), **Files** (lazy tree, markdown rendering, a plain-textarea editor with optimistic-concurrency saves), **History** (git log), **Diff** (working tree).
3. **Plan with Claude** — from the Plans tab, open a planning session: a multi-turn chat running `claude -p` (with `--resume`) inside that repo. The plan file Claude writes is detected from the filesystem and becomes a first-class plan immediately. Per-turn token usage and estimated cost are captured.
4. **Queue orders** — add `ready` plans to the current round from the plan view, the session's produced-plan banner, or the Plans tab. Optional per-order instruction override in the round view.
5. **End Turn** (`#/round`) — all orders execute: sequential within a repo, concurrent across repos, live SSE output streams, per-order cost. Stop-on-failure within a repo; a round-level Stop skips the queue.
6. **Review** — replay each run's output, read each repo's diff, optionally **commit** (the app's only git write: `add -A` + `commit`, no push), tick **Reviewed**, leave **follow-up notes**.
7. **Close Round** — opens Round N+1 with every follow-up (and any unaddressed carry-overs) on its agenda. Past rounds live under **History** (`#/history`) with outcome and cost.

## Configuration

Registry resolution (first match wins): `--registry PATH` → `$C4_ROUNDTABLE_REGISTRY` → `./.roundtable.json` → `~/.config/roundtable/.roundtable.json`. App state (rounds, session transcripts, run output) lives in `~/.roundtable/`, override with `$C4_ROUNDTABLE_HOME`.

Per-project knobs cascade `built-in default → defaults.<key> → projects[].<key>`: `planning_dir`, `implementation_dir`, `allowed_tools`, `model`, `max_turns`, `permission_mode` (implement runs), `planning_permission_mode` (planning sessions, default `acceptEdits`), `instruction_template` (`{path}` = plan file), `planning_template` (`{request}`, `{planning_dir}`), `claude_bin`, `claude_extra_args`. App level: `port` (default 8640). The shipped JSON Schema (`roundtable/schema/roundtable.schema.json`) gives editor completion via the generated `$schema` pointer.

## Costs

Every displayed cost is the **pricing-table estimate** (`claude-usage` over the token counts each run's `result` event reports). The CLI's own `total_cost_usd` is stored and shown only as an informational secondary figure. A model missing from the pricing table renders "n/a", never $0.

## Development

```bash
uv run pytest            # unit + API tests, 100% line+branch coverage gate
uv run ruff check .      # lint
uv run mypy --strict roundtable
bash tests/smoke.sh      # boots the real server against a fake claude, walks the loop
```

## Limitations (MVP)

- Long planning sessions: the CLI owns conversation state; a session that outgrows its context is handled by starting a fresh session per plan.
- The per-project lock serializes planning turns and implement runs **within one server process** — two server processes against the same repo are not cross-process-locked (docket has the same limitation).
- Commit is the only git write: no push, no branch operations, no PR automation.
- One round open at a time; End Turn is always a human act (no scheduled rounds).
- The file editor is a plain textarea (existing files + create-by-path); no rename/delete, no syntax highlighting.
- No auth, no remote access, no HTTPS — `127.0.0.1` only, by design.
