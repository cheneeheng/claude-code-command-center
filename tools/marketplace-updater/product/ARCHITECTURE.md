# marketplace-updater — Architecture

A scheduled job that keeps Claude Code plugins current. It refreshes configured marketplaces,
then updates the plugins from them that are installed for configured repos. It drives the
`claude` CLI and nothing else.

## System context

```mermaid
flowchart LR
    task["Task Scheduler<br/>every N minutes"] --> worker["marketplace-updater.ps1"]
    cfg[("config.json<br/>marketplaces, repos")] --> worker
    worker -->|"marketplace update X"| cli["claude CLI"]
    worker -->|"plugin list --json"| cli
    worker -->|"plugin update id --scope s<br/>cwd = repo"| cli
    worker --> log[("run.log")]
```

## Key flow — one run

```mermaid
sequenceDiagram
    participant W as worker
    participant C as claude CLI
    loop each marketplace X
        W->>C: plugin marketplace update X
        C-->>W: exit code (non-zero: X skipped, run fails)
    end
    W->>C: plugin list --json
    C-->>W: installs with id, scope, projectPath
    loop install with scope local/project, projectPath in repos, marketplace refreshed
        W->>C: plugin update id --scope s (cwd = projectPath)
    end
    W->>W: log, exit 0 or 2
```

## Key Decisions

- **Shell out to the CLI, never edit its state.** The CLI owns marketplaces and the plugin cache, so
  the tool survives changes to their file formats.
- **Repos are matched through `projectPath` from `plugin list --json`.** That is the only record of
  which repo a local or project install belongs to.
- **No `-y`.** An unattended run does not accept a marketplace-declared command on anyone's behalf.
- **The interval lives in the task, the rest in `config.json`.** Marketplaces and repos change
  often and are re-read every run. The interval needs a task re-registration.
- **Windows only.** Matches `file-sync`; a cron twin was left out because nobody asked for it.
- **2026-11-05: the install dir is `~/.claude-command-center/marketplace-updater/`, not
  `%LOCALAPPDATA%\claude-automation\`.** The user wants every file a command-center tool installs
  or writes in its own folder next to the manifest. Install keeps a 0.1.x `run.log` and deletes the
  old dir, only after the task is re-registered, so a failed registration never points the task at
  a deleted worker. A run holding the old dir open makes install warn rather than fail.
