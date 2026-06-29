# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A small, dependency-free library for reading Claude Code's installed plugins and their members —
skills, agents, and hooks — from local config. It models one external contract — the
`~/.claude/plugins/installed_plugins.json` registry plus each plugin's `skills/<name>/SKILL.md`,
`agents/<name>.md`, and `hooks/hooks.json` layout — and turns it into typed records. It exists
because two members need this exact parsing: the `claude-component-browser` app and the
`per-project-plugin-toggler` app.

## Commands

See README.md for the public API. Managed with `uv`. For a quick sanity check, parse/type-check the
changed file (`uv run python -m py_compile src/claude_plugins/<file>.py`); lint/type-check with
`uv run ruff check .` and `uv run mypy src`.

## Code structure (`src/claude_plugins/`)

- `__init__.py` — the public surface (`__all__`). This is the API boundary.
- `plugins.py` — registry reading and scope bucketing: `load_installed_plugins`, `plugins_base`,
  `normalise_path`, `loose_bases`.
- `members.py` — member parsing: `parse_frontmatter`, `load_plugin_skills`, `load_plugin_agents`,
  `load_plugin_hooks`, and the `PluginMember` / `PluginHook` dataclasses.

## Invariants — do not break these

- **This is a library: keep `dependencies = []`.** Stdlib only. Never add a runtime dependency for
  what a few lines of stdlib do, and never add web-service deps.
- **The public API is `__init__.py` / `__all__`.** Public signature changes are semver-relevant and
  break consumers (`claude-component-browser`, `per-project-plugin-toggler`) — change deliberately.
- **`PluginMember.path` is server-side detail.** Strip it before sending member lists to untrusted
  clients. Consumers rely on this contract; do not start leaking paths to clients.
- **A parallel Node.js copy of this logic lives in the toggler's `vscode-extension/extension.js`**
  (a Python library can't serve that surface). It is a registered intentional duplicate — keep the
  two in sync and see `../../docs/shared-plugin-logic.md` when changing parsing behaviour.
- **Missing/unreadable registry → empty buckets**, not an exception. Preserve graceful degradation.
- **Honour `$C4_CLAUDE_DIR`** (first pathsep entry) via `plugins_base`.

## Conventions

- Google-style docstrings on public symbols; type hints everywhere; mypy `strict = true`; ruff
  (line length 88). Never edit `uv.lock` by hand.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
