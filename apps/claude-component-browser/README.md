# claude-component-browser

A local web app that lists and searches every **Claude Code component — skill, agent, and hook —
on this machine**, from **installed plugins** and from **loose** (non-plugin) skills/agents
authored directly under a `.claude` dir. It reads `~/.claude/plugins/installed_plugins.json`,
buckets plugins by **scope** (`local` / `project` / `user`, matched against the directory you
launch it from), enumerates each plugin's `skills/<name>/SKILL.md`, `agents/*.md`, and
`hooks/hooks.json`, then adds loose skills/agents from `~/.claude` (user) and `<project>/.claude`
(project), and serves a searchable single-page UI — click an item to read its full details.

```bash
cd /your/project && uv run python /path/to/server.py   # http://127.0.0.1:7780
uv run python server.py --port 9001
```

Run it from a project root so `local`/`project`-scope plugins and the project's loose `.claude`
skills/agents resolve; `user`-scope members always show. Each item carries a **kind** badge
(skill / agent / hook), a scope badge, and a `loose` badge for non-plugin components. When a loose
component and a plugin one share a kind+name, the loose one wins and the other is shown
**shadowed** (struck through); loose project beats loose user beats plugin.

- **Search** filters by name, description, plugin, source, scope, or kind.
- **Detail pane** shows the selected item's body — a skill/agent's markdown, or a rendered view of
  a hook's event, matcher, and actions.
- Honours `$CLAUDE_DIR` (first entry) to point at a different config dir.

The plugin/skill/agent/hook reading lives in the
[`claude-plugins`](../../libs/claude-plugins/) library (stdlib only); this app is a thin server +
UI over it, managed with `uv`. Binds to `127.0.0.1`. The member list never exposes file paths; the
body endpoint takes a bounds-checked index into the server's own scan (no user-supplied paths, so
no traversal).

> The reading logic is shared with
> [`per-project-plugin-toggler`](../per-project-plugin-toggler/) via `claude-plugins` — see
> [`docs/shared-plugin-logic.md`](../../docs/shared-plugin-logic.md). Skills come from
> marketplaces like [`cheneeheng/agent-skills`](https://github.com/cheneeheng/agent-skills).

> The skills you see come from marketplaces like [`cheneeheng/agent-skills`](https://github.com/cheneeheng/agent-skills).
> To enable/disable plugins per project, see the [`per-project-plugin-toggler`](../per-project-plugin-toggler/) app.
