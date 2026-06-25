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

### `tools/` — single-purpose utilities & scripts

| Tool | What it does |
|------|--------------|
| [`statusline-hook`](tools/statusline-hook/) | Claude Code `StatusLine` hook (PowerShell/Bash/Python) printing a colour-coded one-liner; optionally exports JSONL for the `usage-dashboard` app. |
| [`session-name-date-prefixer`](tools/session-name-date-prefixer/) | Prefix Claude Code session names with the date. |
| [`claude-md-devcontainer-sync`](tools/claude-md-devcontainer-sync/) | Keep `CLAUDE.md` and the devcontainer `CLAUDE.md` in sync. |
| [`settings-devcontainer-sync`](tools/settings-devcontainer-sync/) | Keep Claude settings and the devcontainer settings in sync. |
| [`scheduled-automations`](tools/scheduled-automations/) | Unattended Claude Code automations that run on a schedule (daily/weekly summaries and lessons). |

> `statusline-hook`, `session-name-date-prefixer`, `claude-md-devcontainer-sync`,
> `settings-devcontainer-sync`, and the `usage-dashboard` app were originally one
> `claude-automation` suite; see [`docs/automation-suite.md`](docs/automation-suite.md)
> for the combined overview.

### `libs/` — shared libraries

Empty for now. Planned: a dependency-light parser for `~/.claude/**/*.jsonl` transcripts,
extracted from `usage-dashboard` / `multi-repo-plan-runner` / `scheduled-automations` that all
read those logs today.

## Repository layout

```
apps/      full applications you run
tools/     single-purpose utilities & scripts
libs/      shared libraries (planned)
plugins/   packaged Claude Code skills/plugins (planned)
docs/      monorepo-wide docs
```

## License

[Apache-2.0](LICENSE) for the whole repository.

## Plan & decisions

The build plan lives in [`.agents_workspace/planning/v1/SKELETON.md`](.agents_workspace/planning/v1/SKELETON.md);
decisions are logged in [`.agents_workspace/DECISION_LOG.md`](.agents_workspace/DECISION_LOG.md).
