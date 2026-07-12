# CLAUDE.md

Guidance for Claude Code when working in this repository. Each member also has its own
`CLAUDE.md`; that member-level file wins for anything inside its folder.

## What this repo is

A monorepo of independent projects centered on Claude Code, grouped by category:

```
apps/      full applications you run (cross-repo-file-diff, multi-repo-plan-runner,
           multi-repo-workspace, per-project-plugin-toggler, usage-dashboard,
           claude-component-browser)
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
`claude-component-browser` and `per-project-plugin-toggler`'s Python server, with only the
toggler's VSCode **Node** port left as
a deliberate copy a Python library can't serve.

Members are **self-contained**: each keeps its own README, tests, and CLAUDE.md.
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
- **Testing:** a member earns a **smoke test** when it has a runtime surface the static checks
  (`ruff`/`mypy`/`py_compile`) can't verify — it boots a process/serves endpoints, exposes a CLI
  entrypoint, or imports another member at runtime. The smoke starts the real thing and asserts the
  happy path only (it boots and one endpoint/exit code responds); this is the class of failure
  static analysis misses (a green `mypy` that still won't run). Prefer a smoke test over a unit
  suite for thin stdlib-glue apps/tools, whose risk is wiring not logic. **Libraries** (`libs/`)
  have no boot surface — cover their public API with **unit tests** instead. Members with real
  branching logic want unit tests regardless (`multi-repo-plan-runner` is the worked example:
  `pytest` with a 100% coverage gate). Trivial static glue with no runtime surface stays on the
  static checks only — do not add ceremony. Whatever tests a member has, **wire them as a required
  check** so they gate merges; an un-required test that can go red without blocking manufactures
  false confidence.
- **Naming:** member folders are descriptive (a newcomer should know what each does from the
  name). Files inside members keep their original names.
- **Env vars:** every environment variable this repo defines and reads is prefixed `C4_`
  (the repo's own namespace), so it never collides with Claude Code's or the OS's variables.
  Current vars: `C4_CLAUDE_DIR` (config dir override), `C4_CLAUDE_META_DIR` (claude-meta dir
  for scheduled digests), `C4_STATUSLINE_EXPORT` (statusline JSONL export opt-in),
  `C4_STATUSLINE_LIVE_TIMEOUT` (usage-dashboard live-session timeout),
  `C4_PLAN_PRICE_USD` (usage-dashboard monthly plan price for the Plan Value card),
  `C4_ROUNDTABLE_REGISTRY` (multi-repo-workspace registry path override),
  `C4_ROUNDTABLE_HOME` (multi-repo-workspace state dir, default `~/.roundtable`). OS-provided
  vars (`USERPROFILE`, `LOCALAPPDATA`, `PATH`, …) are not ours and keep their names.
- **History:** relocate/rename with `git mv` to preserve history.
- **Scheduled tasks:** a member that registers a Windows Task Scheduler task uses its own folder
  name as the task name (e.g. `usage-dashboard`), registered under the shared task folder
  `\ClaudeAutomation`. This keeps task names collision-free and self-identifying to the member.
- **Docs:** **one `README.md` per member** (apps/tools/libs/setup) plus the root README,
  which is the catalog. Deeper end-user docs live under a member's `docs/` (e.g.
  `multi-repo-plan-runner/docs/guide/`, `per-project-plugin-toggler/docs/user-guide-*.md`) and the
  README links into them — do not split a member into multiple READMEs. Two sanctioned exceptions:
  `per-project-plugin-toggler/vscode-extension/README.md`, which ships with the VSIX and is
  rendered on the VSCode marketplace page; and `scheduled-session-digests`, whose four
  independently installable digests (`daily-summary`, `daily-lessons`, `weekly-lessons`,
  `git-sync`) each keep their own README under their sub-folder, linked from the member's top
  README. Independently released components keep their own `CHANGELOG.md` (Keep a Changelog
  format) tracking that component's tagged releases; the repo as a whole also keeps a root
  `CHANGELOG.md` once it cuts its first repo-wide release. Components not yet released
  independently carry no `CHANGELOG.md` until their first release. No per-member planning docs and
  no per-member decision logs: build planning is ephemeral, and agent decisions go in the active
  `.agents_workspace/DECISION_LOG.md` (historical per-member logs are frozen in
  `.agents_workspace/archive/decision-log.md`).
- **Releases:** two independent axes with non-overlapping tag namespaces. A *component* release is
  a SemVer tag prefixed with the component's short alias (e.g. `pppt-vX.Y.Z` for
  `per-project-plugin-toggler`) and triggers only that component's release workflow — the plugin
  toggler's is `.github/workflows/release-extension.yml`, which asserts the tag matches
  `vscode-extension/package.json`, builds `skills-toggle.vsix` on Ubuntu, and attaches it to a
  GitHub release (it does NOT publish to the VSCode Marketplace). A *whole-repo* release is a bare
  `vX.Y.Z` tag; that namespace is reserved but not yet wired (no `release-repo.yml` / root
  `CHANGELOG.md` yet), deferred until the first repo-wide release. The bare `v*` namespace never
  collides with a prefixed `<alias>-v*` one, so the axes coexist. To cut a component release: bump
  the manifest version, update that component's `CHANGELOG.md`, merge via PR, then
  `git tag -a <alias>-vX.Y.Z` on `main` and push the tag — the workflow does the rest. See
  `docs/releasing.md` for the prefix→component table and the per-component release steps.

## Scope discipline

Work within the member you were asked to change. Do not retrofit conventions across unrelated
members in a single change. Adding a new member: place it under the right category folder, give
it a self-descriptive name, a README, and (for Python) a `uv` project.

## Decisions

- Active decision log: `.agents_workspace/DECISION_LOG.md` (append here when you resolve
  genuine ambiguity).
- Archived per-member logs: `.agents_workspace/archive/decision-log.md` (frozen history).
