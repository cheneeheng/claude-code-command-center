# Shared plugin-reading logic — intentional duplication register

Some members independently implement the **same** logic for reading Claude Code's installed
plugins and skills. This is a **deliberate copy**, not an accident. This file is the register:
if you change the behaviour in one place, change it in all of them.

## What is duplicated

Reading `~/.claude/plugins/installed_plugins.json` and each plugin's `skills/<name>/SKILL.md`:

| Logic | Purpose |
|-------|---------|
| `normalise_path` | Cross-platform path normalisation for project-root comparison. |
| `load_installed_plugins(project_root)` / `loadInstalledPlugins(projectRoot)` | Bucket installed plugins by **scope** (`local` / `project` / `user`), matching `projectPath` against the project root. |
| `parse_skill_frontmatter` / `parseSkillFrontmatter` | Extract `(name, description)` from a SKILL.md's YAML frontmatter (regex; handles inline and `>-`/`\|` block scalars). |
| skill enumeration | Walk `<installPath>/skills/*/SKILL.md`. |

## The copies (keep in sync)

| # | Location | Language |
|---|----------|----------|
| 1 | `apps/skill-browser/server.py` | Python |
| 2 | `apps/per-project-plugin-toggler/html/server.py` | Python |
| 3 | `apps/per-project-plugin-toggler/vscode-extension/extension.js` | Node |

## Why copied instead of a `libs/` library

A `libs/claude-plugins` would satisfy our library bar (cohesive domain + ≥2 consumers), but:

- The plugin-toggler is deliberately **stdlib / zero-dependency** and ships a **parallel Node.js
  implementation** (#3). A Python library can't serve the Node surface, so it would only de-dupe
  two of the three copies while forcing a dependency onto an app that advertises having none.
- The shared surface is small (~3 short functions).

So the cost of the library (new package + refactors + a new dependency on the toggler) outweighs
the benefit today. **Revisit extracting `libs/claude-plugins` if a fourth (Python) consumer
appears, or if this logic grows materially.**

## Known intentional differences (not drift)

- The toggler returns **mock** plugin data when `installed_plugins.json` is missing (a dev aid);
  `skill-browser` returns empty (it is a read-only viewer).
- `skill-browser` is **non-strict** mypy here specifically so its copy stays parallel to the
  toggler's JSON-reading code rather than diverging through added type annotations.
- Display quirks inherited from the shared parser (e.g. a quoted `name: "x"` renders with quotes)
  apply to all copies — fix them in all three if you fix them at all.
