# skill-browser

A local web app that lists and searches every **Claude Code skill installed on this machine**.
It reads `~/.claude/plugins/installed_plugins.json`, buckets plugins by **scope**
(`local` / `project` / `user`, matched against the directory you launch it from), finds each
plugin's `skills/<name>/SKILL.md`, and serves a searchable single-page UI — click a skill to
read its full instructions.

```bash
cd /your/project && uv run python /path/to/server.py   # http://127.0.0.1:7780
uv run python server.py --port 9001
```

Run it from a project root so `local`/`project`-scope plugins resolve; `user`-scope skills
always show. Each skill carries a scope badge.

- **Search** filters by skill name, description, plugin, or scope.
- **Detail pane** shows the selected skill's `SKILL.md` body.
- Honours `$CLAUDE_DIR` (first entry) to point at a different config dir.

Stdlib only (`dependencies = []`), managed with `uv`. Binds to `127.0.0.1`.
The skill list never exposes file paths; the body endpoint takes a bounds-checked index into the
server's own scan (no user-supplied paths, so no traversal).

> The scope-bucketing and SKILL.md parsing here are intentionally shared (by copy) with
> [`per-project-plugin-toggler`](../per-project-plugin-toggler/) — see
> [`docs/shared-plugin-logic.md`](../../docs/shared-plugin-logic.md). Skills come from
> marketplaces like [`cheneeheng/agent-skills`](https://github.com/cheneeheng/agent-skills).

> The skills you see come from marketplaces like [`cheneeheng/agent-skills`](https://github.com/cheneeheng/agent-skills).
> To enable/disable plugins per project, see the [`per-project-plugin-toggler`](../per-project-plugin-toggler/) app.
