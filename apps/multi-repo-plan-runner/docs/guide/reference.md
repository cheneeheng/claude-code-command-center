# Reference

Appendix: commands, controls, the lifecycle, and registry fields. For task walkthroughs start at
the [guide index](index.md).

## CLI

```
docket [--registry PATH] <command>
```

`--registry PATH` is a global option (it precedes the subcommand) and applies to every subcommand.

| Command | Options | Purpose |
|---------|---------|---------|
| `docket tui` | — | Launch the Textual terminal UI. |
| `docket serve` | `--port N` (default `8765`) | Launch the localhost browser server at `http://127.0.0.1:N`. |
| `docket init` | `--scan ROOT`, `--output PATH`, `--force`, `--merge`, `--dry-run` | Generate or update a `.docket.json` registry. See [Configure the registry](operations/configure-registry.md). |
| `docket doctor` | — | Load the resolved registry and report problems; exits `1` on any error. |

With no command, docket prints help and exits non-zero.

Run via `uv run docket …` (recommended) or `docket …` after a `pip install -e .`.

## TUI key bindings

| Key | Action |
|-----|--------|
| **Enter** | Select the focused plan (renders its body read-only). |
| **i** | Implement the selected plan headless. |
| **Shift+I** | Implement all batch-selected plans. |
| **r** | Run myself — copy the plan body + print the manual command. |
| **m** | Mark the selected plan implemented (manual). |
| **o** | Reopen the selected plan to `ready` (manual). |
| **Space** | Toggle the focused plan in/out of the batch selection. |
| **s** | Stop the active headless run. |
| **q** | Quit. |

Status badges in the tree: `○` ready, `▶` running, `●` implemented.

## Browser controls

- **Plan row** — click to select and view the plan read-only.
- **Implement** — headless run (enabled when `ready` or `implemented`).
- **Run myself** — manual command + copy plan body (enabled when `ready` or `implemented`).
- **Mark implemented** — shown only when `ready`.
- **Reopen** — shown only when `implemented`.
- **Checkbox + Implement selected** — batch submit.
- **Stop** — terminate the active run(s).

## Lifecycle

Status is a closed set: `ready | running | implemented`. It lives only in the sidecar; a plan with
no sidecar is `ready`. Legal transitions:

| From | To | Trigger | Who |
|------|----|---------|-----|
| `ready` | `running` | `headless` | runner, on spawn |
| `implemented` | `running` | `headless` | runner, on re-run spawn |
| `running` | `implemented` | `headless` | runner, on exit code 0 |
| `running` | `ready` | `headless` | runner, on fail/stop |
| `running` | `ready` | `startup_reset` | startup recovery |
| `ready` | `implemented` | `manual` | you (mark implemented) |
| `implemented` | `ready` | `manual` | you (reopen) |

Any transition not in this table is rejected. Manual transitions never produce `running`.

## Sidecar record

`<repo>/.agents_workspace/implementation/<slug>.json`:

```json
{
  "slug": "feature-x/ITER_01",
  "status": "implemented",
  "history": [
    { "ts": "2026-06-20T13:45:02Z", "from": "ready", "to": "running",
      "trigger": "headless", "run_id": "…", "rc": null },
    { "ts": "2026-06-20T13:52:10Z", "from": "running", "to": "implemented",
      "trigger": "headless", "run_id": "…", "rc": 0 }
  ]
}
```

## Registry fields

Top-level: `projects` (required list) and `instruction_template` (optional). Per-project: `name`,
`path` (both required), `allowed_tools`, `model`, `max_turns` (optional). Full descriptions,
defaults, and validation errors: [Configure the registry](operations/configure-registry.md).

## Headless invocation

For a headless run docket invokes, with the working directory set to the project's `path`:

```
claude -p \
  --output-format stream-json --verbose \
  --permission-mode acceptEdits \
  --max-turns <max_turns> \
  --allowedTools <comma-joined allowed_tools> \
  [--model <model>]
```

- The **instruction** (not the plan body) is piped on stdin. It names the plan file
  (`.agents_workspace/planning/<slug>.md`); Claude Code opens the file itself.
- The instruction comes from the registry's `instruction_template` (or docket's built-in default),
  with `{path}` substituted — overridable per run at submit time.
- Output is parsed from `stream-json` NDJSON events into the readable log lines you see.

> These Claude Code flags can drift across CLI versions. If a headless run fails to start, check
> `claude --help` for the installed version and confirm `--output-format stream-json [--verbose]`,
> `--permission-mode`, and `--allowedTools` are still accepted.

## HTTP API (browser frontend)

The browser page calls a small same-origin JSON API on `127.0.0.1`. You normally never touch it
directly; it's listed here for operators debugging the page.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/` | The single-page UI. |
| GET | `/static/*` | JS/CSS assets. |
| GET | `/api/projects` | All projects + each plan's `{slug, title, status}`. |
| GET | `/api/plan?project=&slug=` | One plan's full body + status + history. |
| GET | `/api/instruction-template` | The effective default instruction template. |
| GET | `/api/runcmd?project=&slug=` | The "run it yourself" command. |
| POST | `/api/implemented` | Manual `ready → implemented`. |
| POST | `/api/reopen` | Manual `implemented → ready`. |
| POST | `/api/implement` | Submit a batch of headless runs. |
| GET | `/api/stream?run_id=` | SSE stream of one run's output. |
| POST | `/api/stop` | Terminate a run (and its project's remaining batch). |

`slug` may contain `/` for nested plans and is URL-encoded in query strings.
