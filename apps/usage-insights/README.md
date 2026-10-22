# usage-insights

A local dashboard over your Claude Code usage that helps you decide what to change. One page
answers three questions:

- **What will I spend?** Tokens and cost so far this week and month, the forecast with a low/high
  band, the month so far drawn against its forecast, a 30-day pace strip with its average and
  peak, and the month forecast per project.
- **Where does it go?** Totals for the range (cost, tokens, sessions, cost per session, and how
  much input came from cache), projects ranked by cost with their change against the previous
  period, each model's share of cost, the token mix, and the top sessions.
- **What should I fix?** Every skill and subagent with a health status, tool calls ranked by count,
  and the built-in tools and MCP servers you never call.

It replaces [`usage-dashboard`](../usage-dashboard/). Data comes from Claude Code's transcripts
(`~/.claude/projects/**/*.jsonl`), copied into a local store, so your history outlives Claude
Code's transcript cleanup.

## Install

Install from this checkout. You need [`uv`](https://docs.astral.sh/uv/) and
[`bun`](https://bun.sh/) on PATH. Each script builds the web frontend and installs the
`usage-insights` command with `uv tool install --editable`.

**Windows** (PowerShell):

```powershell
./scripts/usage-insights-setup.ps1 -Action install
```

This also registers the Task Scheduler task `\ClaudeAutomation\usage-insights\export`, which
copies new transcripts into the store daily at 12:00 and at logon, with no console window. You can
also install it through [`setup/command-center.ps1`](../../setup/) as the member
`usage-insights`.

**macOS and Linux** (bash):

```bash
bash scripts/usage-insights-setup.sh install
```

The script prints a crontab line for a daily export and does not edit your crontab. Add it with
`crontab -e`:

```
0 12 * * * <uv tool bin dir>/usage-insights export
```

The dashboard also exports on every launch and every refresh, on every OS, so the scheduled export
only matters for keeping history when you don't open the dashboard for a while.

**Uninstall:** `-Action uninstall` (Windows) or `uninstall` (bash) removes the task and the command.
The store is kept, and the script prints its path.

## Use

```
usage-insights                   # export, then serve http://127.0.0.1:8090/ and open the browser
usage-insights export            # export only
```

| Option | Default | Meaning |
|--------|---------|---------|
| `--port` | `8090` | Port to serve on. If a running `usage-insights` already holds it, the command opens the browser on it and exits. |
| `--host` | `127.0.0.1` | Address to bind. |
| `--claude-dir DIR` | `$C4_CLAUDE_DIR` or `~/.claude` | Claude config dir to read. Repeat it for several. |
| `--no-open` | off | Don't open the browser. |

Press Ctrl+C to stop the server. The range buttons (7d, 30d, 90d, all) scope the spend and health
counts. The forecast always covers the current week (Monday to Sunday) and calendar month.

## Chat

With an Anthropic API key set, a **Chat** button opens a drawer beside the dashboard. Ask a
question such as "Which projects cost more than last month?" or "Show my Opus spend per week",
and the agent answers by adding panels to the dashboard. It can also add sections, move panels,
and remove them. Without a key, the button is greyed out, its tooltip names the variable to set,
and the dashboard works as before. After setting the key, stop the running `usage-insights` and
start it again: a server started before the key existed keeps the chat off.

| Variable | Default | Meaning |
|----------|---------|---------|
| `C4_USAGE_INSIGHTS_API_KEY` | unset | Anthropic API key for the chat. Unset turns the chat off. |
| `C4_USAGE_INSIGHTS_MODEL` | `claude-sonnet-5-5` | Model the chat runs on. |

- **Why not `ANTHROPIC_API_KEY`:** Claude Code reads that variable too. Setting it in your user
  environment for this dashboard could switch your own `claude -p` runs to API billing.
- **Cost:** every message spends API credit on your key, billed per token at the model's API
  price, not through a Claude subscription. A question usually takes a few model requests,
  because the agent checks each query before placing its panel. A run stops after 8 requests.
- **Figures come from the store, never from the model:** a generated panel holds a typed query,
  and the server computes what it shows, the same way it computes the default panels. The agent
  cannot write a figure into a panel.
- **Your layout is saved** to `layout.json` in the store dir and survives a restart. **Reset
  layout** in the top bar deletes it and brings back the default panels, which also removes every
  generated panel. A saved layout keeps the default panels that existed when it was saved, so a
  default panel added in a later version appears only after Reset.
- **Chats live in server memory:** a restart loses the conversation, never the layout. New chat
  starts over.

## Network sources

The scheduled `usage-insights export` (not the dashboard itself) refreshes three lists at most
once a day and caches them in `reference.json` in the store dir. Each falls back to a list built
into the app when its fetch fails, and the export prints one line per fetch and per failure.

| Data | Source | Fallback |
|------|--------|----------|
| Model prices | LiteLLM's public price file on GitHub (Anthropic entries) | The price table in `claude-usage` |
| Built-in tool names | The Claude Code docs tools table | A hand-kept list |
| Built-in agent names | Your local `claude` CLI, asked with a prompt-free `initialize` request, so no model turn runs and no API key is passed to it | A hand-kept list |

The dashboard says under each cost forecast which prices it used: "Prices from LiteLLM" with the
fetch date, or "Built-in prices".

## The store

The store is a SQLite file at `~/.usage-insights/usage.db`, or `$C4_USAGE_INSIGHTS_HOME/usage.db`.

- **Retention:** rows are never deleted. When Claude Code removes an old transcript, the sessions,
  messages, and events already exported stay in the store.
- **Incremental:** an export re-reads only transcripts whose size or modification time changed.
- **Untimed lines:** a transcript line with no timestamp is stored but counts in no dashboard
  figure, because it has no date to place it on. The export's message count includes it.
- **Cost** is computed when the page loads, from the fetched prices over the price table in
  `claude-usage`, so a price fix needs no re-export. Models missing from both are listed as
  unpriced instead of costed at $0.
- **Beside it** in the same dir: `reference.json` (the fetched lists above) and `layout.json`
  (your edited layout, when there is one).
- **Upgrades:** when a new version changes the store's schema, the next export copies the old file
  to `usage.db.bak.v<old version>` and rebuilds from the transcripts still on disk. Rows for
  transcripts Claude Code already deleted are lost from the new store, and the export prints a
  warning. Each schema version gets its own backup, so a later upgrade never overwrites one.

## Health statuses

Each skill and subagent gets the first status that matches, judged over all history in the store:

| Status | Meaning |
|--------|---------|
| `never_used` | Installed, never used. |
| `troubled` | At least 3 uses in the last 30 days, and at least 20% of them were followed by you interrupting Claude in the same session within 15 minutes. |
| `declining` | Uses in the last 30 days are below half of the 30 days before, and the earlier window had at least 4. |
| `unused_lately` | Last used more than 30 days ago. |
| `healthy` | Everything else. |

The **Invoked** column says whether Claude chose the skill (`auto`), you typed it as a slash
command (`typed`), or both. Names that are used but not installed (built-in skills, removed
plugins) show with source `unknown`. Installed but disabled plugins count as installed, so their
unused skills show as `never_used`.

## Develop

```
uv sync
uv run pytest                    # exporter, aggregation, and a booted server
uv run ruff check . && uv run mypy src
cd web && bun install && bun run dev   # Vite on :5173, proxying /api to 127.0.0.1:8090
cd web && bun run typecheck && bun run test && bun run build
```

`bun run build` writes the frontend into `src/usage_insights/static/`, which the server serves.
The design and its reasons are in [`product/ARCHITECTURE.md`](product/ARCHITECTURE.md) and the
build plans in [`product/plans/`](product/plans/). The tests never reach the network or the
`claude` CLI, and the chat's tests need no API key.
