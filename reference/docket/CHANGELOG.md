# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-06-21

Layered configuration. The flat `projects.json` registry is replaced by a three-layer
`.docket.json` (top-level app settings · `defaults` · `projects[]`) merged per-knob into
resolved projects, with `docket init` / `docket doctor` to scaffold and validate it.

### Changed

- **BREAKING — registry format and filename.** `projects.json` is replaced by `.docket.json`,
  a three-layer registry (top-level app settings, `defaults`, `projects[]`) merged per-knob
  (`CODE_DEFAULTS` → `defaults.<k>` → `project.<k>`) into resolved `Project` configs.
  Resolution order is now `--registry PATH` → `$DOCKET_REGISTRY` → `./.docket.json` →
  `~/.config/docket/.docket.json`. Migration: run `docket init --scan <dir>` to scaffold a new
  `.docket.json`, or `docket init --merge` to add repos to an existing one.

### Added

- **`docket init`** — scan a directory to scaffold or refresh `.docket.json`; `--merge` adds
  newly found repos in place without clobbering existing entries.
- **`docket doctor`** — validate the resolved config and exit non-zero on any error.
- **Published JSON schema** (`docket/schema/docket.schema.json`, referenced via `$schema`) for
  editor validation of `.docket.json`.

### Fixed

- **Headless UTF-8 on non-UTF-8 locales** — the `claude -p` subprocess pipes are now pinned to
  `encoding="utf-8", errors="replace"`, fixing `UnicodeEncode/DecodeError` on Windows (cp1252)
  when writing the instruction's em-dash or reading Claude's stream-json output.
- **TUI batch-select** — `space` now toggles batch selection (previously consumed by the
  tree's expand/collapse), and selection follows the cursor instead of the last Enter/click, so
  multi-select operates on the highlighted plan.

[2.0.0]: https://github.com/cheneeheng/docket/releases/tag/v2.0.0

## [1.0.0] - 2026-06-20

First stable release. docket is a local, single-user command-center over many Claude Code
repos: it reads plan markdown from each repo's `.agents_workspace/planning/`, tracks each
plan's lifecycle in a docket-owned JSON sidecar, and implements plans manually or headless
via `claude -p`.

### Added

- **Plan discovery and lifecycle tracking** — reads plans from each registered repo's
  `.agents_workspace/planning/`; a docket-owned sidecar under
  `.agents_workspace/implementation/<slug>.json` tracks a closed-set lifecycle
  (`ready | running | implemented`) with a fixed transition table and recorded history.
- **Headless implementation** — runs plans via `claude -p`, piping a short instruction that
  names the plan file (never the plan body), with per-project `threading.Lock` serializing
  same-repo runs and concurrent runs across projects.
- **Textual TUI** (`docket tui`) — terminal interface that streams one run at a time.
- **Localhost browser UI** (`docket serve`) — stdlib `ThreadingHTTPServer` with a
  hand-written JSON API and SSE stream; no framework, no build step. Binds `127.0.0.1` only.
- **Batch orchestration** — server-side `RunManager` for running multiple plans, with
  startup recovery (`reset_stale_runs`) for runs interrupted by a crash.
- **Registry configuration** — `projects.json` registry with resolution order
  `--registry PATH` → `$DOCKET_REGISTRY` → `./projects.json` → `~/.config/docket/projects.json`;
  per-project `model`, `max_turns`, and `instruction_template` overrides.
- **Path-traversal guard** — every external slug passes through `core.safe_slug`, keeping
  access inside `planning/` / `implementation/`.
- **Atomic sidecar writes** — temp file + `os.replace`, with a bounded Windows retry on
  transient `PermissionError`.
- **Documentation** — `ARCHITECTURE.md` (diagrams + key decisions), `CLAUDE.md`, and a
  user/operator guide under `docs/guide`.
- **Test suite** — `tests/` (`unit/` + `api/`) at 100% line+branch coverage, gated in
  `pyproject.toml`.

### Security

- Both frontends bind to `127.0.0.1` only; localhost-only binding is the entire auth model
  for this single-user MVP. docket never handles API keys (the headless runner shells out to
  an already-authenticated `claude` CLI).

[1.0.0]: https://github.com/cheneeheng/docket/releases/tag/v1.0.0
