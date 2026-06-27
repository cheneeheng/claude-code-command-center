# Claude Code Command Center

The ultimate monorepo for working with **Claude Code** — apps you run, utility tools,
and shared libraries, all centered on Claude Code.

Each member keeps its own `README.md`, `CHANGELOG.md`, and `CLAUDE.md`. This front page is
the catalog; click into a folder for full docs.

## Catalog

### `apps/` — full applications you run

| App | What it does |
|-----|--------------|
| [`cross-repo-file-diff`](apps/cross-repo-file-diff/) | Survey many local repos from one board; diff and copy files across any two of them. Serverless, no build (Chromium only). |
| [`multi-repo-plan-runner`](apps/multi-repo-plan-runner/) | A command center over the Claude Code repos you work across: surface every plan and its lifecycle status, and run plans without leaving the tool. |
| [`per-project-plugin-toggler`](apps/per-project-plugin-toggler/) | Enable/disable Claude Code plugins per project from a browser UI or inside VSCode; browse and install from known marketplaces. |
| [`usage-dashboard`](apps/usage-dashboard/) | Local web dashboard for token usage, cost by model, rate limits, and sessions. Reads Claude Code transcripts; live rate limits come from the optional `statusline-hook` tool. |
| [`skill-browser`](apps/skill-browser/) | Local web app to search and read every Claude Code skill installed on your machine, grouped by plugin. |

### `tools/` — single-purpose utilities & scripts

| Tool | What it does |
|------|--------------|
| [`statusline-hook`](tools/statusline-hook/) | Claude Code `StatusLine` hook (PowerShell/Bash/Python) printing a colour-coded one-liner; optionally exports JSONL for the `usage-dashboard` app. |
| [`session-name-date-prefixer`](tools/session-name-date-prefixer/) | Prefix Claude Code session names with the date. |
| [`claude-md-sync`](tools/claude-md-sync/) | Keep two `CLAUDE.md` files in sync across two folders (newer wins). |
| [`settings-sync`](tools/settings-sync/) | Keep two Claude `settings.json` files in sync across two folders (newer wins, excluded keys preserved). |
| [`scheduled-session-digests`](tools/scheduled-session-digests/) | Unattended scheduled Claude Code runs that digest your session transcripts into daily/weekly summaries and lessons. |
| [`usage-report`](tools/usage-report/) | CLI summary of token usage and estimated cost across sessions — the terminal counterpart to `usage-dashboard`. |

> `statusline-hook`, `session-name-date-prefixer`, `claude-md-sync`,
> `settings-sync`, and the `usage-dashboard` app were originally one
> `claude-automation` suite; see [`docs/automation-suite.md`](docs/automation-suite.md)
> for the combined overview.

### `libs/` — shared libraries

| Library | What it does |
|---------|--------------|
| [`claude-usage`](libs/claude-usage/) | Dependency-free library that reads Claude Code's `~/.claude/projects/**/*.jsonl` transcripts into per-session token/cost data, plus the model pricing table. |

A library earns a place here only with a **cohesive domain** and **≥2 real consumers** — not as
a utilities junk drawer. `claude-usage` qualifies: it models one external contract (the transcript
layout) and is consumed by both the `usage-dashboard` app and the `usage-report` CLI.

## Repository layout

```
apps/      full applications you run
tools/     single-purpose utilities & scripts
libs/      shared libraries
plugins/   packaged Claude Code skills/plugins (planned)
docs/      monorepo-wide docs
```

## Related repositories

- [`cheneeheng/agent-skills`](https://github.com/cheneeheng/agent-skills) — the Claude Code
  skills/plugins marketplace (kept as a separate repo). It's the source of many skills you'd see
  in the `skill-browser` app here.

## License

[Apache-2.0](LICENSE) for the whole repository.

## Plan & decisions

The build plan lives in [`.agents_workspace/planning/v1/SKELETON.md`](.agents_workspace/planning/v1/SKELETON.md);
decisions are logged in [`.agents_workspace/DECISION_LOG.md`](.agents_workspace/DECISION_LOG.md).
