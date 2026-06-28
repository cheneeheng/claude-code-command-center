# CLAUDE.md

Guidance for Claude Code when working in this repository. Each member also has its own
`CLAUDE.md`; that member-level file wins for anything inside its folder.

## What this repo is

A monorepo of independent projects centered on Claude Code, grouped by category:

```
apps/      full applications you run (cross-repo-file-diff, multi-repo-plan-runner,
           per-project-plugin-toggler, usage-dashboard, plugin-component-browser)
tools/     single-purpose utilities & scripts (statusline-hook,
           session-name-date-prefixer, file-sync,
           scheduled-session-digests, usage-report)
libs/      shared libraries (claude-usage, claude-plugins)
setup/     unified installer for the installable tools/ members + per-machine manifest
plugins/   packaged Claude Code skills/plugins (planned)
docs/      monorepo-wide docs
```

**app vs tool:** an **app** is a destination you open and interact with through a UI (web page,
TUI, dashboard, editor extension). A **tool** is plumbing that does one job, usually invoked by
something else (a hook, a scheduled task, a CLI shim) or run-and-forget, with no interactive
surface. When a member bundles both (e.g. the statusline hook + its dashboard), split them.

**when something belongs in `libs/`:** only with a **cohesive domain** *and* **≥2 real
consumers** — never a utilities junk drawer, and never a single-consumer extraction. Extract on
the second consumer, not the first. `claude-usage` (Claude Code local-data access, used by
`usage-dashboard` and `usage-report`) is the worked example.

**intentional duplication:** sometimes a library doesn't fit (e.g. a consumer is deliberately
zero-dependency, or has a parallel non-Python implementation). When logic is copied across
members on purpose, register it in `docs/shared-plugin-logic.md` and add a `Cross-reference:`
comment in each copy, so the copies are kept in sync. That file is the worked example: the
plugin/skill/agent/hook reader is the `claude-plugins` library, consumed by
`plugin-component-browser` and `per-project-plugin-toggler`'s Python server, with only the
toggler's VSCode **Node** port left as
a deliberate copy a Python library can't serve.

Members are **self-contained**: each keeps its own README, CHANGELOG, tests, and CLAUDE.md.
The umbrella adds a catalog and shared conventions; it does not flatten or rewrite members.

**`setup/` (umbrella infra, not a member):** a single `command-center.ps1` that installs/uninstalls
the installable `tools/` members and tracks state in a manifest under `~/.claude-command-center/`. It
is a thin **delegator** — it calls each member's own setup script and never reimplements install logic,
so the no-cross-member-dependency rule still holds (members stay independent; only `setup/` knows them
all). Register a new installable tool by adding a descriptor to `setup/registry.ps1`.

## Conventions

- **License:** single root `LICENSE` (Apache-2.0) covers the whole repo. Members do not carry
  their own license files.
- **Python:** every Python member is managed with `uv` (`pyproject.toml` + `uv.lock`). Run code
  with `uv run …`; never edit `uv.lock` by hand. Lint/format with `ruff` (line length 88).
  Stdlib-only tools keep `dependencies = []` and `[tool.uv] package = false`.
- **Naming:** member folders are descriptive (a newcomer should know what each does from the
  name). Files inside members keep their original names.
- **Env vars:** every environment variable this repo defines and reads is prefixed `C4_`
  (the repo's own namespace), so it never collides with Claude Code's or the OS's variables.
  Current vars: `C4_CLAUDE_DIR` (config dir override), `C4_CLAUDE_META_DIR` (claude-meta dir
  for scheduled digests), `C4_STATUSLINE_EXPORT` (statusline JSONL export opt-in). OS-provided
  vars (`USERPROFILE`, `LOCALAPPDATA`, `PATH`, …) are not ours and keep their names.
- **History:** relocate/rename with `git mv` to preserve history.

## Scope discipline

Work within the member you were asked to change. Do not retrofit conventions across unrelated
members in a single change. Adding a new member: place it under the right category folder, give
it a self-descriptive name, a README, and (for Python) a `uv` project.

## Plan & decisions

- Build plan: `.agents_workspace/planning/v1/SKELETON.md`
- Decision log: `.agents_workspace/DECISION_LOG.md`
