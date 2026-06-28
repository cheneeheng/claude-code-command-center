# claude-plugins

A small, dependency-free library for reading **Claude Code's installed plugins**
and their members — skills, agents, and hooks — from your local config.

It models one well-defined external contract — the
`~/.claude/plugins/installed_plugins.json` registry and each plugin's
`skills/<name>/SKILL.md`, `agents/<name>.md` and `hooks/hooks.json` layout — and
turns it into typed records. It exists because more than one member needs this
exact parsing: the [`claude-component-browser`](../../apps/claude-component-browser/) app and the
[`per-project-plugin-toggler`](../../apps/per-project-plugin-toggler/) app both
consume it.

## API

```python
from pathlib import Path
from claude_plugins import load_installed_plugins, load_plugin_skills

buckets = load_installed_plugins(Path.cwd())   # {"local": [...], "project": [...], "user": [...]}
for entry in buckets["user"]:
    for skill in load_plugin_skills(entry["installPath"]):
        print(skill.name, "—", skill.description)
```

| Symbol | Purpose |
|--------|---------|
| `load_installed_plugins(project_root)` | Bucket installed plugins by **scope** (`local`/`project`/`user`), matching `projectPath` against the project root. Empty buckets if the registry is missing/unreadable. |
| `plugins_base()` | Resolve `<claude_dir>/plugins` (honours the first pathsep entry of `$C4_CLAUDE_DIR`). |
| `normalise_path(p)` | Cross-platform path normalisation for project-root comparison. |
| `parse_frontmatter(path, fallback="")` | Extract `(name, description)` from a markdown file's YAML frontmatter (regex; inline and `>-`/`>`/`\|` block scalars). |
| `load_plugin_skills(install_path)` | Read `skills/<name>/SKILL.md` → `list[PluginMember]`. |
| `load_plugin_agents(install_path)` | Read flat `agents/*.md` → `list[PluginMember]`. |
| `load_plugin_hooks(install_path)` | Read `hooks/hooks.json` → `list[PluginHook]`. |
| `PluginMember` | Frozen dataclass: `name`, `description`, `path` (source `.md`; server-side). |
| `PluginHook` | Frozen dataclass: `event`, `matcher`, `actions` (`[{type, detail}]`). |

`PluginMember.path` is server-side detail — strip it before sending member lists
to untrusted clients.

> A parallel **Node.js** copy of this logic lives in the plugin-toggler's
> `vscode-extension/extension.js` (a Python library can't serve that surface).
> It is a registered intentional duplicate — see
> [`docs/shared-plugin-logic.md`](../../docs/shared-plugin-logic.md).

Stdlib only (`dependencies = []`), strict-typed, managed with `uv`.
