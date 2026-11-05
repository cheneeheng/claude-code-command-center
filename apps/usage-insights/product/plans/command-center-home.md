---
title: usage-insights, keep the store under ~/.claude-command-center
status: built
created: 2026-11-05
---

## Goal

Move the default store dir (`usage.db` with its SQLite `-wal`/`-shm` files and
`usage.db.bak.v*` backups, `reference.json`, `layout.json`) from `~/.usage-insights` to
`~/.claude-command-center/usage-insights`, so every file the command-center apps and tools own
sits next to its manifest. The flow that matters: the user re-runs setup, the existing store moves
over with every session it holds, and the dashboard shows the same history as before.

## Scope

**In:**

- `store.store_path()`: the default becomes `~/.claude-command-center/usage-insights/usage.db`.
  `C4_USAGE_INSIGHTS_HOME` still overrides it. Read-only fallback: when the env var is unset, the
  new dir does not exist and `~/.usage-insights` does, it returns the old path. Without it, the
  editable `uv tool` install picks up the new default on `git pull`, before setup is re-run, and
  the next export or dashboard start creates an empty store in the new dir; setup would then find
  both and move nothing, and the history would drop out of the dashboard.
- The fallback covers `reference.json` and `layout.json` too, as long as their callers derive the
  dir from `store_path().parent` (checked while building).
- Setup (`usage-insights-setup.ps1` and `.sh`) moves the old store before anything else: when
  `C4_USAGE_INSIGHTS_HOME` is unset, `~/.usage-insights` exists, and the new dir does not, it moves
  the whole old dir to the new path (creating `~/.claude-command-center` if needed) and prints
  both paths. If both exist it moves nothing and warns, naming both, so no store is overwritten.
  Before the move it stops and disables the existing `export` task (a re-run finds it registered,
  and a first export can take minutes), and a failed move (a running dashboard or export holds
  `usage.db` open) stops setup with a message to close the dashboard and re-run. The task is
  re-registered, enabled, after the move.
- The `.ps1` / `.sh` store paths printed by setup.
- Docs that name the default: README, `docs/store.md`, the root `README.md` line naming
  `~/.usage-insights`, CLAUDE.md, `product/ARCHITECTURE.md` (diagram node and a Key
  Decision), the root CLAUDE.md env var line for `C4_USAGE_INSIGHTS_HOME`.
- `pyproject.toml` minor version bump.

**Out:**

- A move inside the Python app: a path lookup with a move side effect would run on every command.
  The read-only fallback keeps such a user on the old store until setup moves it.
- Built plans and fixes under `product/` that mention `~/.usage-insights`: they are records.
- The web test fixture string `/home/x/.usage-insights/usage.db`: it is sample data, not a default.

## Phases

### Phase 1: default path and setup move

- **Check:** unit tests for `store_path()` (env var unset, `Path.home()` monkeypatched to a temp
  dir): the new default when neither dir exists, the old path when only the old one exists, the
  new path when both exist, written red first, then the existing suite
  (`uv run pytest`), `ruff`, `mypy` as CI runs them. The setup move is checked by running setup on
  this machine: before, record the session count from `usage-insights` API or a `sqlite3` count of
  the sessions table; after, the new dir holds the same count and `~/.usage-insights` is gone.

### Phase 2: docs and setup/

- **Check:** CI green on the PR.

## Record

- 2026-11-05: Plan reviewed in a fresh context: two blocking findings (an editable install picks up
  the new default before setup moves the store; a re-run's export task can hold `usage.db`) and
  two advisory ones, all folded in above.
- 2026-11-05: Built. `tests/test_store_path.py`: red first (new default and both-exist cases
  returned `~/.usage-insights/usage.db`), green after; full suite 91 passed, `ruff check` and
  `mypy src` clean. `setup/command-center.ps1 install -Member usage-insights` on this machine:
  before, `~/.usage-insights/usage.db` held 2394 sessions and 56357 messages; after, the new dir
  holds the same counts, the old dir is gone, the export task is `Ready`, and a real
  `usage-insights export` wrote into the new store. `docs/store.md` names no path, so it needed no
  change.
- 2026-11-05 PR: #86 https://github.com/cheneeheng/claude-code-command-center/pull/86
