# Shared plugin-reading logic — library + intentional Node duplicate

Several members read the **same** thing: Claude Code's installed plugins and their members
(skills, agents, hooks). The **Python** implementation is now a single library,
[`libs/claude-plugins`](../libs/claude-plugins/). A **Node.js** copy survives in the VSCode
extension because a Python library can't serve that surface — that copy is a **deliberate**
duplicate, and this file is its register: if you change the behaviour, change it in both.

## What the logic does

Reading `~/.claude/plugins/installed_plugins.json` and each plugin's
`skills/<name>/SKILL.md`, `agents/<name>.md`, and `hooks/hooks.json`:

| Logic | Purpose |
|-------|---------|
| `normalise_path` | Cross-platform path normalisation for project-root comparison. |
| `load_installed_plugins(project_root)` / `loadInstalledPlugins(projectRoot)` | Bucket installed plugins by **scope** (`local` / `project` / `user`), matching `projectPath` against the project root. |
| `parse_frontmatter` / `parseSkillFrontmatter` | Extract `(name, description)` from a markdown file's YAML frontmatter (regex; handles inline and `>-`/`>`/`\|` block scalars). |
| skill / agent / hook enumeration | Walk `<installPath>/skills/*/SKILL.md`, `agents/*.md`, `hooks/hooks.json`. |

## The implementations

| # | Location | Language | Role |
|---|----------|----------|------|
| 1 | `libs/claude-plugins` | Python | **Canonical** library. |
| 2 | `apps/claude-component-browser/server.py` | Python | Consumes #1. |
| 3 | `apps/per-project-plugin-toggler/html/server.py` | Python | Consumes #1. |
| 4 | `apps/per-project-plugin-toggler/vscode-extension/extension.js` | Node | **Intentional duplicate** of #1 — keep in sync by hand. |

## Why the Node copy is not de-duplicated

The VSCode extension is a **parallel Node.js implementation** (#4). A Python library can't serve a
Node surface, so #4 stays a copy. The Python copies (#2, #3) are gone — they now import #1, which
is the extraction the previous version of this register predicted.

## Python-only: loose (non-plugin) component discovery

`claude-component-browser` also lists **loose** skills/agents authored directly under a
`.claude` dir (`~/.claude` and `<project>/.claude`), discovered via the library's
`loose_bases()` + the existing member readers. This is **Python-only**: the Node copy (#4)
still reads installed plugins only. That is a deliberate gap, not drift — the toggler's VSCode
surface toggles plugins and has no loose-component view. If the Node copy ever grows a loose
view, port `loose_bases` there and update this section.

## Known intentional differences (not drift)

- The toggler returns **mock** plugin data when `installed_plugins.json` is missing (a dev aid),
  via a thin wrapper in `html/server.py` over the library; the library itself and
  `claude-component-browser` return empty (read-only viewers).
- The library raises nothing on a malformed `installed_plugins.json` — it returns empty buckets;
  the Node copy should match (return empty rather than throw).
- Display quirks inherited from the shared parser (e.g. a quoted `name: "x"` renders with quotes)
  apply to all copies — fix them in the library and #4 together.
