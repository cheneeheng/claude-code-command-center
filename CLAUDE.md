# CLAUDE.md

Guidance for Claude Code when working in this repository. Each member also has its own
`CLAUDE.md`; that member-level file wins for anything inside its folder.

## What this repo is

A monorepo of independent projects centered on Claude Code, grouped by category:

```
apps/      full applications you run (cross-repo-file-diff, multi-repo-plan-runner,
           per-project-plugin-toggler, usage-dashboard)
tools/     single-purpose utilities & scripts (statusline-hook,
           session-name-date-prefixer, claude-md-devcontainer-sync,
           settings-devcontainer-sync, scheduled-automations, usage-report)
libs/      shared libraries (claude-usage)
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

Members are **self-contained**: each keeps its own README, CHANGELOG, tests, and CLAUDE.md.
The umbrella adds a catalog and shared conventions; it does not flatten or rewrite members.

## Conventions

- **License:** single root `LICENSE` (Apache-2.0) covers the whole repo. Members do not carry
  their own license files.
- **Python:** every Python member is managed with `uv` (`pyproject.toml` + `uv.lock`). Run code
  with `uv run …`; never edit `uv.lock` by hand. Lint/format with `ruff` (line length 88).
  Stdlib-only tools keep `dependencies = []` and `[tool.uv] package = false`.
- **Naming:** member folders are descriptive (a newcomer should know what each does from the
  name). Files inside members keep their original names.
- **History:** relocate/rename with `git mv` to preserve history.

## Scope discipline

Work within the member you were asked to change. Do not retrofit conventions across unrelated
members in a single change. Adding a new member: place it under the right category folder, give
it a self-descriptive name, a README, and (for Python) a `uv` project.

## Plan & decisions

- Build plan: `.agents_workspace/planning/v1/SKELETON.md`
- Decision log: `.agents_workspace/DECISION_LOG.md`
