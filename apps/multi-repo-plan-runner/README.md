# docket

A single local command-center over the ~10 Claude Code repos you work across. docket reads a
JSON registry of your repos, surfaces every plan and its lifecycle status in one view, and lets
you implement plans — singly or as a per-project sequential batch — without leaving the tool.

Plans are markdown files **you author with the planning skill**, living under each repo's
`.agents_workspace/planning/`. **docket never creates, edits, or deletes a plan** — it only
reads them. The mutable state docket owns lives separately under
`.agents_workspace/implementation/`: one JSON sidecar per plan holding that plan's lifecycle
status and full transition history. Delete `implementation/` and you only lose status/history,
never a plan.

## Lifecycle

A plan moves through `ready → running → implemented`, driven two ways:

- **Headless** — docket runs `claude -p` in the repo and streams the output. The stdin prompt is
  a short instruction that **names the plan file**; the plan body is never piped (Claude Code
  reads the file itself). docket sets `running` on spawn, `implemented` on success.
- **Manual** — you run Claude Code yourself; docket hands you a copy-pasteable command and you
  **mark it implemented** by hand. No subprocess, no `running` state — but the transition is
  still logged.

Submit many plans at once: docket groups them by project and runs each project's plans
sequentially (stop-on-failure per project), with different projects running concurrently.

## Install

```
pip install -e .
```

Requires Python 3.11+. The only pip dependency is `textual` (the browser side is pure stdlib).
The `claude` CLI must be separately installed and authenticated (BYO-CLI) — docket shells out to
it and does not handle API keys.

## Registry

The registry is a single `.docket.json` (a sample is committed). Resolution order, first match
wins: `--registry PATH` → `$DOCKET_REGISTRY` → `./.docket.json` → `~/.config/docket/.docket.json`.

Don't start from a blank file — generate one and edit:

```
docket init                 # write a full default ./.docket.json
docket init --scan ~/code   # also pre-populate projects from repos with a planning/ dir
docket init --scan ~/code --merge   # re-run later: add only newly-found repos, keep your edits
```

It has three layers — top-level app settings, a `defaults` baseline, and per-project overrides:

```json
{
  "$schema": "docket/schema/docket.schema.json",
  "port": 8765,
  "defaults": {
    "model": "claude-sonnet-4-6",
    "max_turns": 40,
    "instruction_template": "Read the plan at {path} and implement it fully. ..."
  },
  "projects": [
    { "name": "pyxyflow", "path": "~/code/pyxyflow" },
    { "name": "mcp-harness", "path": "~/code/mcp-harness", "max_turns": 30 }
  ]
}
```

Each project needs `name` (unique) + `path` (a git repo; `~`/`$VARS` expanded) and may override
any `defaults` knob: `allowed_tools`, `instruction_template`, `model`, `max_turns`,
`permission_mode`, `planning_dir`, `implementation_dir`, `claude_bin`, `claude_extra_args`. A
knob left unset everywhere falls back to a built-in default. List overrides **replace** (not
merge) the defaults list. The committed `$schema` pointer gives editors autocomplete + validation;
docket itself never reads the schema at runtime.

## Run

```
docket tui                  # Textual terminal UI
docket serve --port 8765    # localhost browser page -> http://127.0.0.1:8765
docket doctor               # check the resolved config (paths, permission_mode, claude on PATH)
```

`serve`'s default port comes from `port` in the config (the `--port` flag overrides). All
subcommands accept `--registry PATH`. The browser server binds to `127.0.0.1` only.

## MVP limitations

- The per-project lock serializes same-repo headless runs **within one process**. Running the
  TUI and the server against the **same repo simultaneously** is not cross-process-locked.
- The MVP TUI streams one run at a time (the browser streams concurrent per-project batches).
- docket leaves working-tree changes; it does **not** commit. Review the diff yourself
  (`git diff` / your editor) — that is the final step.

See [CHANGELOG.md](CHANGELOG.md) for release history.
