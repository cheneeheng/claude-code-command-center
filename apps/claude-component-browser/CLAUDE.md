# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A local web app that lists and searches every Claude Code component — skill, agent, and hook — on
this machine, from installed plugins and from loose (non-plugin) skills/agents authored directly
under a `.claude` dir. It buckets plugins by scope (`local` / `project` / `user`) against the
launch directory, enumerates each plugin's members, adds loose skills/agents from `~/.claude` and
`<project>/.claude`, and serves a searchable single-page UI. A thin server + UI over the
`claude-plugins` library.

## Running

See README.md for full usage. Run from a project root (or pass `--project-dir`) so `local`/
`project`-scope members resolve: `uv run python server.py` (default `http://127.0.0.1:7780`;
`--port` to override). Honours `$C4_CLAUDE_DIR` (first pathsep entry).

For a quick sanity check on an edit, parse/type-check the changed file
(`uv run python -m py_compile server.py`).

## Architecture

- `server.py` — stdlib `ThreadingHTTPServer` + a `Member` dataclass. Scans plugins (via
  `claude-plugins`) and loose `.claude` skills/agents into an ordered in-memory list at request
  time; serves the searchable UI and a body endpoint. All plugin/skill/agent/hook reading is
  delegated to the `claude-plugins` library — do not reimplement parsing here.
- `index.html` / `styles.css` / `app.js` — the single-page UI. `app.js` renders the member list,
  search, sections, and the detail pane; markdown is rendered client-side.
- `markdown-it.min.js` — a vendored, offline copy of markdown-it. Skill/agent bodies are rendered
  with raw HTML escaped.

## Invariants — do not break these

- **Plugin reading lives in `claude-plugins`, not here.** This app is a thin consumer; the parsing
  logic is shared with `per-project-plugin-toggler` via that library — see
  `../../docs/shared-plugin-logic.md`. Do not fork the reader into this app.
- **No file paths cross the wire.** `Member.path`/`body` are server-side only. The member list
  never exposes filesystem paths; the body endpoint takes a bounds-checked index into the server's
  own scan — never a user-supplied path. Preserve this (it is the traversal guard).
- **Binds `127.0.0.1` only** — that is the entire auth story. No new network exposure.
- **Markdown is rendered offline with raw HTML escaped.** Keep markdown-it vendored; do not add a
  CDN/remote dependency, and do not disable HTML escaping.
- **Shadowing order:** loose project beats loose user beats plugin; when a loose and a plugin
  component share kind+name, the loose one wins and the other is shown shadowed. Preserve this
  precedence.

## Conventions

- Python member managed with `uv`; stdlib only apart from the in-repo `claude-plugins` library.
  ruff (line length 88) and mypy `strict = true`.
- New decisions go in the repo-root `.agents_workspace/DECISION_LOG.md`.
