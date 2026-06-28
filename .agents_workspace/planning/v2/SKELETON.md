---
artifact: feature-plan
title: Loose-component discovery + claude-component-browser rename
status: in-progress
created: 2026-06-28
branch: feat/loose-component-discovery
scope: Extend libs/claude-plugins to discover loose (non-plugin) skills and agents
       alongside installed-plugin members, surface them in the browser with
       loose-over-plugin precedence, and rename the browser app to drop "plugin".
---

# Loose-component discovery — Build Plan (v2)

## 1. Goal

`libs/claude-plugins` today reads only **installed plugins** (via
`plugins/installed_plugins.json`). Extend it to also discover **loose** (non-plugin)
components — the skills and agents authored directly under `~/.claude/` (user scope) and
`<project>/.claude/` (project scope). Surface them in the browser, with **loose taking
precedence over plugin** on a name collision. Rename the browser app so its name no longer
says "plugin".

## 2. Decisions (locked with user)

- **Precedence**, high -> low: `project-loose` > `user-loose` > `plugin` (any scope).
  On a `(kind, name)` collision the lower-ranked entry is marked shadowed, not hidden —
  a viewer shows the full picture and badges the winner.
- **Toggler keeps its name** `per-project-plugin-toggler` — it only *toggles* plugins
  (loose components have no native per-project on/off switch; faking one by mutating
  authored/committed files is out of scope).
- **Browser renames** `plugin-component-browser` -> `claude-component-browser`.
- **v1 scope:** loose **skills + agents** only.
  - Deferred (not built speculatively): loose **hooks** (these live inside `settings.json`
    under a `hooks` key — a different shape/reader than plugin `hooks/hooks.json`) and
    **commands** (`.claude/commands/*.md`, not shown by the browser today).

## 3. Key finding (shrinks the work)

The existing member readers are already source-neutral. `load_plugin_skills(base)` reads
`<base>/skills/<name>/SKILL.md`; `load_plugin_agents(base)` reads `<base>/agents/*.md`.
For a loose component the `base` is simply the `.claude` dir instead of a plugin's
`installPath`. **No new reader is required** — only a discovery function that yields the
right base dirs per scope.

## 4. Step 1 — Library (`libs/claude-plugins`)

`plugins.py`:
- Extract `claude_dir() -> Path` — the `$CLAUDE_DIR`-honouring base currently inlined in
  `plugins_base()`. Redefine `plugins_base()` as `claude_dir() / "plugins"`
  (pure refactor, no behaviour change).
- Add:
  ```python
  def loose_bases(project_root: Path) -> dict[str, str]:
      """Scope -> .claude base dir holding loose (non-plugin) components.

      Loose components exist only at user and project scope (there is no 'local'
      loose dir — 'local' is a plugin/settings concept).
      """
      return {
          "user": str(claude_dir()),
          "project": str(Path(project_root) / ".claude"),
      }
  ```
- Export `claude_dir`, `loose_bases` from `__init__.py` / `__all__`.

Precedence/shadow logic stays **out** of the library for now — only the browser consumes
loose components in v1, and the repo rule is "extract on the second consumer". Promote a
precedence resolver into the library when the toggler also surfaces loose components.

## 5. Step 2 — Browser (`server.py` + UI)

- Add `source: str` (`"plugin" | "loose"`) to `Member`; loose entries carry empty
  `plugin/marketplace/version`.
- New loose loop over `loose_bases(project_root)` appending skills + agents
  with `source="loose"`.
- Precedence: after collecting, mark `shadowed=True` on the lower-ranked of any
  `(kind, name)` collision (project-loose > user-loose > plugin). Show all; badge winner.
- UI (`index.html` / `styles.css`): `source` badge + muted style for `shadowed`;
  add source to the filter set.

## 6. Step 3 — Rename sweep (`plugin-component-browser` -> `claude-component-browser`)

`git mv` the folder, then update:
- `pyproject.toml` name; `uv.lock` (regenerate via `uv lock`, never hand-edit).
- App `README.md` / `CLAUDE.md`; `server.py` / `styles.css` self-references.
- Root `README.md` + root `CLAUDE.md` catalog.
- `docs/shared-plugin-logic.md` (browser row only — toggler rows untouched).
- `libs/claude-plugins/README.md` + `__init__.py` docstring (name-drops the consumer).
- `.github/workflows/ci.yml` lines 23 (ruff matrix) + 50 (mypy matrix).

## 7. Step 4 — Sync obligations

- `docs/shared-plugin-logic.md`: record that loose-component discovery is **Python-only**
  for now (the `extension.js` Node copy stays plugin-only until ported) — so it is not
  mistaken for drift.
- `DECISION_LOG.md`: entries for (a) the loose>plugin precedence rule and (b) the rename.

## 8. Sequencing

1. Library refactor + `loose_bases` (+ optional tests).
2. Browser loose loop + precedence + UI.
3. Rename sweep, regenerate lock, fix CI.
4. Docs / Node-register + decision log.

Steps 1-2 are the feature; 3-4 are mechanical.
