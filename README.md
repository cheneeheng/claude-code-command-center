# Claude Code Command Center

The ultimate monorepo for working with **Claude Code** — apps you run, utility tools,
and shared libraries, all centered on Claude Code.

Each member keeps its own `README.md` and `CLAUDE.md` (plus a `CHANGELOG.md` once it is
released independently). This front page is the catalog; click into a folder for full docs.
Releases are tagged per component — see the [release guide](docs/releasing.md).

## Catalog

### `apps/` — full applications you run

| App | What it does |
|-----|--------------|
| [`cross-repo-file-diff`](apps/cross-repo-file-diff/) | Survey many local repos from one board; diff and copy files across any two of them. Serverless, no build (Chromium only). |
| [`multi-repo-plan-runner`](apps/multi-repo-plan-runner/) | A command center over the Claude Code repos you work across: surface every plan and its lifecycle status, and run plans without leaving the tool. |
| [`multi-repo-workspace`](apps/multi-repo-workspace/) | Turn-based workspace over your Claude Code repos (internal name *roundtable*): a board of repos with live git/plan state, in-app Claude Code planning sessions, rounds of orders executed headlessly with live streams and per-run cost, and a review phase with diffs, commits, and carried follow-ups. Successor to `multi-repo-plan-runner`; both share the same lifecycle sidecar format. |
| [`per-project-plugin-toggler`](apps/per-project-plugin-toggler/) | Enable/disable Claude Code plugins per project from a browser UI or inside VSCode; browse and install from known marketplaces. |
| [`usage-dashboard`](apps/usage-dashboard/) | Interactive local web dashboard for token usage, cost, and rate limits: range/project scoping, plan ROI, trend deltas, activity/model/tool profiles, drill-down with shareable URLs, session economics, a live rate-limit trajectory with cap ETA, and Markdown/CSV export. Reads Claude Code transcripts; live rate limits read an optional statusline JSONL export, which no tool in this repo writes yet. |
| [`usage-insights`](apps/usage-insights/) | Local dashboard that helps you decide what to change: this week's and month's token and cost forecast, where spend goes by project, model, and session, and which skills, subagents, and tools are never used, fading, or followed by trouble. Keeps its own transcript store, so history outlives Claude Code's cleanup. Replaces `usage-dashboard`. |
| [`claude-component-browser`](apps/claude-component-browser/) | Local web app to search and read every Claude Code component — skill, agent, and hook — on your machine, from installed plugins and from loose (non-plugin) `.claude` skills/agents, grouped by source. |

### `tools/` — single-purpose utilities & scripts

| Tool | What it does |
|------|--------------|
| [`statusline-hook`](tools/statusline-hook/) | Claude Code statusline (bash + jq, or PowerShell) with model, context, runtime and cost on one row and aligned 5-hour / 7-day rate-limit gauges below. |
| [`session-name-date-prefixer`](tools/session-name-date-prefixer/) | Prefix Claude Code session names with the date. |
| [`file-sync`](tools/file-sync/) | Keep a named file in sync across two folders (newer wins): `CLAUDE.md` (raw copy) and `settings.json` (JSON merge, excluded keys preserved), via one generic engine. |
| [`scheduled-session-digests`](tools/scheduled-session-digests/) | Install once and it runs in the background: every night, headless Claude Code turns each of your new sessions into a lessons-learned file, and every week merges the new lessons into one master file, in a local git repo you own. Also keeps a cleaned copy of each session's transcript. |
| [`agents-workspace-sync`](tools/agents-workspace-sync/) | Daily unattended commit and push of a configured list of `.agents_workspace` repos; each must be a standalone git repo, and each is pushed on the branch it is already on. |
| [`marketplace-updater`](tools/marketplace-updater/) | On a schedule, refreshes the Claude Code marketplaces you list and updates their plugins in the repos you list. Marketplaces, repos, and interval are all config. |
| [`usage-report`](tools/usage-report/) | CLI summary of token usage and estimated cost across sessions — the terminal counterpart to `usage-dashboard`. |

> `statusline-hook`, `session-name-date-prefixer`, `claude-md-sync`,
> `settings-sync`, and the `usage-dashboard` app were originally one
> `claude-automation` suite; see [`docs/automation-suite.md`](docs/automation-suite.md)
> for the combined overview.

### `libs/` — shared libraries

| Library | What it does |
|---------|--------------|
| [`claude-usage`](libs/claude-usage/) | Dependency-free library that reads Claude Code's `~/.claude/projects/**/*.jsonl` transcripts into per-session token/cost data, plus the model pricing table. |
| [`claude-plugins`](libs/claude-plugins/) | Dependency-free library that reads Claude Code's installed plugins and their skills/agents/hooks from local config into typed records. |

A library earns a place here only with a **cohesive domain** and **≥2 real consumers** — not as a
utilities junk drawer. `claude-usage` qualifies (the transcript layout, consumed by the
`usage-dashboard` and `usage-insights` apps and the `usage-report` CLI); so does `claude-plugins`
(the installed-plugin layout, consumed by the `claude-component-browser`,
`per-project-plugin-toggler`, and `usage-insights` apps).

## Installing the tools

The installable `tools/` members (`statusline-hook`, `session-name-date-prefixer`, `file-sync`,
`scheduled-session-digests`) can be installed, uninstalled, and tracked from one place via
[`setup/command-center.ps1`](setup/):

```powershell
./setup/command-center.ps1 status                 # what's installed on this machine
./setup/command-center.ps1 install -Member statusline-hook
./setup/command-center.ps1 install -All           # reads ~/.claude-command-center/config.json
./setup/command-center.ps1 uninstall -All
```

It delegates to each tool's own setup script and records state in a manifest under
`~/.claude-command-center/`. See [`setup/README.md`](setup/README.md). It also manages the two
apps that register a scheduled task, `usage-dashboard` and `usage-insights`. Other apps and
`usage-report` are run on demand, not installed, so they are not managed here.

## Environment variables

Every environment variable this repo defines is prefixed `C4_` (the repo's own namespace) so it
never collides with Claude Code's or the OS's variables:

| Variable | Used by | Purpose |
|----------|---------|---------|
| `C4_CLAUDE_DIR` | `usage-report`, `usage-dashboard`, `usage-insights`, `scheduled-session-digests`, `setup/` | Override the Claude config dir (default `~/.claude`); pathsep-separated, first entry wins. `scheduled-session-digests` reads every entry, at install time. |
| `C4_CLAUDE_META_DIR` | `scheduled-session-digests`, `agents-workspace-sync`, `setup/` | Location of the `claude-meta` directory (default `~/claude-meta`). `scheduled-session-digests` reads it only as the default for `-MetaDir` and never sets it. |
| `C4_STATUSLINE_NOW` | `statusline-hook` | Test-only: pins "now" (epoch seconds) for the golden fixtures. |
| `C4_STATUSLINE_LIVE_TIMEOUT` | `usage-dashboard` | Seconds a session may be idle before dropping out of the live view (default `1800`). |
| `C4_PLAN_PRICE_USD` | `usage-dashboard` | Monthly Claude subscription price; lights up the dashboard's Plan Value (ROI) card when set. |
| `C4_USAGE_INSIGHTS_HOME` | `usage-insights` | Store dir holding `usage.db`, `reference.json`, and `layout.json` (default `~/.usage-insights`). |
| `C4_USAGE_INSIGHTS_API_KEY` | `usage-insights` | Anthropic API key for the chat; unset hides it. Not `ANTHROPIC_API_KEY`, which Claude Code reads too. Each message spends API credit. |
| `C4_USAGE_INSIGHTS_MODEL` | `usage-insights` | Model the chat runs on (default `claude-sonnet-5-5`). |
| `C4_STUB_LIST`, `C4_STUB_LIST_FAIL`, `C4_STUB_LOG` | `marketplace-updater` | Test-only: the stub `claude` CLI's plugin list file, a switch that makes the list fail, and its call log. |
| `C4_ROUNDTABLE_REGISTRY` | `multi-repo-workspace` | Registry file path (overridden by `--registry`, ahead of `./.roundtable.json`). |
| `C4_ROUNDTABLE_HOME` | `multi-repo-workspace` | App state dir — rounds, session transcripts, run output (default `~/.roundtable`). |

OS-provided variables (`USERPROFILE`, `LOCALAPPDATA`, `PATH`, …) are not ours and keep their names.

## Repository layout

```
apps/      full applications you run
tools/     single-purpose utilities & scripts
libs/      shared libraries
setup/     unified installer for the tools/ members + per-machine manifest
plugins/   packaged Claude Code skills/plugins (planned)
docs/      monorepo-wide docs
```

## Related repositories

- [`cheneeheng/agent-skills`](https://github.com/cheneeheng/agent-skills) — the Claude Code
  skills/plugins marketplace (kept as a separate repo). It's the source of many skills you'd see
  in the `claude-component-browser` app here.

## License

[Apache-2.0](LICENSE) for the whole repository.

## Decisions

Agent decisions are logged in `.agents_workspace/DECISION_LOG.md`, with historical per-member
logs consolidated in `.agents_workspace/archive/decision-log.md`. That folder is **not tracked
here** — it is its own git repo on the `claude-code-command-center` orphan branch of a private
`agents-workspace` remote, git-ignored by this repo and pushed daily by
[`agents-workspace-sync`](tools/agents-workspace-sync/).
